# Copyright (C) 2020 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package MirrorCache::Task::FolderSync;
use Mojo::Base 'Mojolicious::Plugin';

use DateTime;

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(folder_sync => sub { _sync($app, @_) });
}

sub _now() {
    return DateTime->now( time_zone => 'local' );
}

sub _sync {
    my ($app, $job, $path, $country) = @_;
    return $job->fail('Empty path is not allowed') unless $path;
    return $job->fail('Trailing slash is forbidden') if '/' eq substr($path,-1) && $path ne '/';

    my $minion = $app->minion;
    return $job->finish('Previous folder sync job is still active')
        unless my $guard = $minion->guard('folder_sync' . $path, 360);

    my $schema = $app->schema;
    my $root   = $app->mc->root;
    $job->note($path => 1);

    my $folder = $schema->resultset('Folder')->find({path => $path});
    unless ($root->is_dir($path)) {
        $folder->update({db_sync_last => _now(), db_sync_priority => 10, db_sync_for_country => ''}) if $folder; # prevent further sync attempts
        return $job->finish("$path is not a dir anymore");
    }

    my $localfiles = $app->mc->root->list_filenames($path);
    my %localfiles = %$localfiles;
    unless ($folder) {
        $folder = $schema->resultset('Folder')->find_or_create({path => $path});
        foreach my $file (sort keys %localfiles) {
            $file = $file . '/' if !$root->is_remote && $root->is_dir("$path/$file") && $path ne '/';
            $file = $file . '/' if !$root->is_remote && $root->is_dir("$path$file") && $path eq '/';
            $schema->resultset('File')->create({folder_id => $folder->id, name => $file, size_txt => $localfiles{$file}{'size'}, dt => $localfiles{$file}{'dt'}});
        }
        $job->note(created => $path, count => scalar(keys %localfiles));

        # Task may be explicitly scheduled for particular country or have country in the DB
        if ($folder->db_sync_for_country) {
            if ($country) {
                $country = '' unless $country eq $folder->db_sync_for_country;
            } else {
                $country = $folder->db_sync_for_country;
            }
        }
        $folder->update({db_sync_last => _now(), db_sync_priority => 10, db_sync_for_country => ''});
        $app->emit_event('mc_path_scan_complete', {path => $path, tag => $folder->id});
        $minion->enqueue('mirror_scan' => [$path, $country] => {priority => 7});
        return;
    };
    return $job->fail("Couldn't create folder $path in DB") unless $folder && $folder->id;

    my $folder_id = $folder->id;
    my %dbfileids = ();
    for my $file ($schema->resultset('File')->search({folder_id => $folder_id})) {
        my $basename = $file->name;
        next unless $basename;
        $dbfileids{$basename} = $file->id;
    }
    my %dbfileidstodelete = %dbfileids;

    my $cnt = 0;
    for my $file (sort keys %localfiles) {
        if ($dbfileids{$file}) {
            delete $dbfileidstodelete{$file};
            next;
        }
        $file = $file . '/' if !$root->is_remote && $root->is_dir("$path/$file") && $path ne '/';
        $file = $file . '/' if !$root->is_remote && $root->is_dir("$path$file") && $path eq '/';
        $schema->resultset('File')->create({folder_id => $folder->id, name => $file, size_txt => $localfiles{$file}{'size'}, dt => $localfiles{$file}{'dt'} });
        $cnt = $cnt + 1;
    }
    my @idstodelete = values %dbfileidstodelete;
    $schema->storage->dbh->do(
      sprintf(
        'DELETE FROM file WHERE id IN(%s)', 
        join ',', ('?') x @idstodelete
      ),
      {},
      @idstodelete,
    ) if @idstodelete;

    # Task may be explicitly scheduled for particular country or have country in the DB
    if ($folder->db_sync_for_country) {
        if ($country) {
            $country = '' unless $country eq $folder->db_sync_for_country;
        } else {
            $country = $folder->db_sync_for_country;
        }
    }
    $folder->update({db_sync_last => _now(), db_sync_priority => 10, db_sync_for_country => ''});
    $job->note(updated => $path, count => $cnt, for_country => $country );
    $minion->enqueue('mirror_scan' => [$path, $country] => {priority => 7} ) if $cnt;
    $app->emit_event('mc_path_scan_complete', {path => $path, tag => $folder->id});
}

1;
