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

# a lot of this is inspired (and even in parts copied) from Minion (Artistic-2.0)
package MirrorCache::WebAPI::Plugin::Backstage;
use Mojo::Base 'Mojolicious::Plugin';

use Minion;
use DBIx::Class::Timestamps 'now';
use MirrorCache::Schema;
use Mojo::Pg;

has app => undef, weak => 1;
has 'dsn';

sub new {
    my ( $class, $app ) = @_;
    my $self = $class->SUPER::new;
    return $self->app($app);
}

my @permanent_jobs =
  qw(folder_sync_schedule_from_misses folder_sync_schedule mirror_scan_schedule_from_misses cleanup stat_agg_schedule);

sub register_tasks {
    my $self = shift;

    my $app = $self->app;
    $app->plugin($_)
      for (
        qw(MirrorCache::Task::MirrorScanScheduleFromMisses),
        qw(MirrorCache::Task::MirrorScanScheduleFromPathErrors),
        qw(MirrorCache::Task::MirrorScan),
        qw(MirrorCache::Task::MirrorLocation),
        qw(MirrorCache::Task::MirrorProbe),
        qw(MirrorCache::Task::FolderSyncScheduleFromMisses),
        qw(MirrorCache::Task::FolderSyncSchedule),
        qw(MirrorCache::Task::FolderSync),
        qw(MirrorCache::Task::Cleanup),
        qw(MirrorCache::Task::StatAggSchedule),
      );
    if (defined $ENV{MIRRORCACHE_PERMANENT_JOBS}) {
        @permanent_jobs = split /[:,\s]+/, $ENV{MIRRORCACHE_PERMANENT_JOBS};
    }
}

sub register {
    my ( $self, $app, $config ) = @_;

    $self->app($app) unless $self->app;
    my $schema = $app->schema;

    my $conn = Mojo::Pg->new;
    if ( ref $schema->storage->connect_info->[0] eq 'HASH' ) {
        $self->dsn( $schema->dsn );
        $conn->username( $schema->storage->connect_info->[0]->{user} );
        $conn->password( $schema->storage->connect_info->[0]->{password} );
    }
    else {
        $self->dsn( $schema->storage->connect_info->[0] );
    }
    $conn->dsn( $self->dsn() );

    $app->plugin( Minion => { Pg => $conn } );
    $self->register_tasks;

    # Enable the Minion Admin interface under /minion
    my $auth =
      $app->routes->under('/minion')->to('session#ensure_operator');
    $app->plugin( 'Minion::Admin' => { route => $auth } );

    my $backstage = MirrorCache::WebAPI::Plugin::Backstage->new($app);
    $app->helper( backstage => sub { $backstage } );

    $app->hook(
        before_server_start => sub {
            my $every = $ENV{MIRRORCACHE_PERMANENT_JOBS_CHECK_INTERVAL} // 15 * 60;
            $self->check_permanent_jobs;
            Mojo::IOLoop->next_tick(
                sub {
                    Mojo::IOLoop->recurring(
                        $every => sub {
                            $self->check_permanent_jobs;
                        }
                    );
                }
            );
        }
    ) if scalar @permanent_jobs;
}

sub check_permanent_jobs {
    my $app    = shift->app;
    my $minion = $app->minion;
    my $jobs   = $minion->jobs(
        {
            tasks  => \@permanent_jobs,
            states => [ 'inactive', 'active' ]
        }
    );
    my $cnt          = 0;
    my %need_restart = map { $_ => 1 } @permanent_jobs;
    while ( my $info = $jobs->next ) {
        $cnt++;
        $app->log->error('Too many permanent jobs running')
          if $cnt == 10;
        return
          if $cnt > 100;    # prevent spawning too many jobs, shouldnot happen

        $need_restart{ $info->{task} } = 0;
    }

    for my $task ( sort keys %need_restart ) {
        next unless $need_restart{$task};
        $app->log->warn("Haven't found running $task, starting it...");
        $minion->enqueue($task);
    }
}

# counts the number of jobs for a certain task in the specified states
sub count_jobs {
    my ( $self, $task, $states ) = @_;
    my $res = $self->app->minion->backend->list_jobs(0, undef, {tasks => [$task], states => $states});
    return ( $res && exists $res->{total} ) ? $res->{total} : 0;
}

# raсe condition here souldn't be big issue
sub enqueue_unless_scheduled_with_parameter_or_limit {
    my ( $self, $task, $arg1, $arg2 ) = @_;
    my $minion = $self->app->minion;
    my $res = $minion->backend->list_jobs(0, 1000, {tasks => [$task], states => ['inactive','active']});
    return 0 unless ($res || !exists $res->{total} || $res->{total} > 1000-1);
    $res = $minion->backend->list_jobs(0, 1, {tasks => [$task], states => ['inactive','active'], notes => [$arg1] });
    return -1 unless ( $res || !exists $res->{total} || $res->{total} > 0 );
    return $minion->enqueue($task => [($arg1, $arg2)] => {priority => 10} => {notes => { $arg1 => 1 }} );
}


1;

=encoding utf8

=head1 NAME

MirrorCache::WebAPI::Plugin::Backstage - The Minion job queue

=head1 SYNOPSIS

    $app->plugin('MirrorCache::WebAPI::Plugin::Backstage');

=head1 DESCRIPTION

L<MirrorCache::WebAPI::Plugin::Backstage> is the WebAPI job queue (and a tiny wrapper
around L<Minion>).

=cut
