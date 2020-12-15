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
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package MirrorCache::WebAPI::Plugin::RootRemote;
use Mojo::Base 'Mojolicious::Plugin';
use Mojolicious::Types;
use Mojo::Util ('trim');
use Mojo::UserAgent;
use Encode ();
use URI::Escape ('uri_unescape');
use File::Basename;

use Data::Dumper;

sub singleton { state $root = shift->SUPER::new; return $root; };

my $rooturl;
my $rooturllen;
my $rooturls; # same as $rooturl just s/http:/https:
my $rooturlslen;
my $types = Mojolicious::Types->new;
my $app;
my $uaroot = Mojo::UserAgent->new->max_redirects(10)->request_timeout(1);

sub register {
    (my $self, $app) = @_;
    $rooturl = $app->mc->rootlocation;
    $rooturllen = length $rooturl;
    $rooturls = $rooturl =~ s/http:/https:/r;
    $rooturlslen = length $rooturls;
    $app->helper( 'mc.root' => sub { $self->singleton; });
}

sub is_remote {
    return 1;
}

sub is_reachable {
    my $res = 0;
    eval {
        my $tx = $uaroot->get($rooturl);
        $res = 1 if $tx->result->code < 399;
    };
    return $res;
}

sub is_file {
    my $rooturlpath = $rooturl . $_[1];
    my $ua = Mojo::UserAgent->new;
    my $res;
    eval {
        my $ua = Mojo::UserAgent->new->max_redirects(10);
        my $tx = $ua->head($rooturlpath);
        $res = $tx->result;
    };
    return ($res && !$res->is_error && !$res->is_redirect);
}

sub is_dir {
    my $res = is_file($_[0], $_[1] . '/');
    return $res;
}

sub render_file {
    my ($self, $c, $filepath) = @_;
    return $c->redirect_to($self->location($c, $filepath));
}

sub location {
    my ($self, $c, $filepath) = @_;
    $filepath = "" unless $filepath;
    return $rooturls . $filepath if $c && $c->req->is_secure;
    return $rooturl . $filepath;
}

sub list_filenames {
    my $self    = shift;
    my $dir     = shift;
    my $tx = Mojo::UserAgent->new->get($rooturl . $dir . '/');
    return undef unless $tx->result->code == 200;
    my $dom = $tx->result->dom;
    return _parse_html($dom);
}

sub _by_filename {
    $b->{dir} cmp $a->{dir} ||
    $a->{name} cmp $b->{name};
}

sub list_files_from_db {
    my $self    = shift;
    my $urlpath = shift;
    my $folder_id = shift;
    my $dir = shift;
    my @res   =
        ( $urlpath eq '/' )
        ? ()
        : ( { url => '../', name => 'Parent Directory', size => '', type => '', mtime => '' } );
    my @files;
    my @childrenfiles = $app->schema->resultset('File')->search({folder_id => $folder_id});

    my $cur_path = Encode::decode_utf8( Mojo::Util::url_unescape( $urlpath ) );
    for my $child ( @childrenfiles ) {
        my $basename = $child->name;
        my $url  = Mojo::Path->new($cur_path)->trailing_slash(0);
        my $is_dir = '/' eq substr($basename, -1)? 1 : 0;
        $basename = substr($basename, 0, -1) if $is_dir;
        push @{ $url->parts }, $basename;
        if ($is_dir) {
            $basename .= '/';
            $url->trailing_slash(1);
        }
        my $mime_type = $types->type( _get_ext($basename) || 'txt' ) || 'text/plain';

        push @files, {
            url   => $url,
            name  => $basename,
            size  => 0,
            type  => $mime_type,
            mtime => '',
            dir   => $is_dir,
        };
    }
    push @res, sort _by_filename @files;
    return \@res;
}

sub list_files {
    my $self    = shift;
    my $urlpath = shift;
    my $dir     = shift;
    my @res   =
        ( $urlpath eq '/' )
        ? ()
        : ( { url => '../', name => 'Parent Directory', size => '', type => '', mtime => '' } );
    my @files;
    my $children = $self->list_filenames($dir);

    my $cur_path = Encode::decode_utf8( Mojo::Util::url_unescape( $urlpath) );
    for my $basename ( sort keys %$children ) {
        my $file = "$dir/$basename";
        my $furl  = Mojo::Path->new($rooturl . $cur_path)->trailing_slash(0);
        my $is_dir = (substr $file, -1) eq '/' || $self->is_dir($file);
        if ($is_dir) {
            # directory points to this server
            $furl = Mojo::Path->new($cur_path)->trailing_slash(0);
            push @{ $furl->parts }, $basename;
            $furl = $furl->trailing_slash(1);
        } else {
            push @{ $furl->parts }, $basename;
        }

        my $mime_type =
            $is_dir
            ? 'directory'
            : ( $types->type( _get_ext($file) || 'txt' ) || 'text/plain' );
        my $mtime = 'mtime';

        push @files, {
            url   => $furl,
            name  => $basename,
            size  => $children->{$basename}{size} || '?',
            type  => $mime_type,
            mtime => $children->{$basename}{dt} || '?',
            dir   => $is_dir,
        };
    }
    push @res, sort _by_filename @files;
    return \@res;
}

sub _get_ext {
    $_[0] =~ /\.([0-9a-zA-Z]+)$/ || return;
    return lc $1;
}

sub _parse_html {
    my $dom = shift;
    # TODO move root html tag to config?
    my @items;
    my $res;
    my @tags = qw/table ul pre/;
    for my $i (0 .. $#tags) {
        my $tag = $tags[$i];
        for my $ul ($dom->find($tag)->each) {
            if ($tag eq 'pre') {
                $res = _parse_html_pre($ul);
            } elsif ($tag eq 'ul') {
                $res = _parse_html_ul($ul);
            } elsif ($tag eq 'table') {
                $res = _parse_html_table($ul);
            }
            return $res if $res;
        }
    }
    return undef;
}

sub _parse_html_pre {
    my $dom = shift;
    my $lines = $dom->all_text;
    my @links = $dom->find('a')->each;
    my %res;
    for my $link (@links) {
        my $text = trim $link->text;
        my $href = $link->attr->{href};

        next unless $href;
        next unless $text;
        if ('/' eq substr($href, -1)) {
            $href = basename($href) . '/';
        } else {
            $href = basename($href);
        }
        $href = uri_unescape($href);

        next unless $text eq $href;
        my $size = undef;
        my $dt = undef;
        if ($lines =~ /^\s+$text\s+([1-2][0-9]{3}-[0-1][0-9]-[0-3][0-9]\s[0-9]{2}:[0-9]{2})\s+(-|[0-9]+[KMG]?)\s*$/mi) {
            $dt = $1;
            $size = $2;
        }
        $res{$text} = { dt => $dt, size => $size };
    }
    return \%res;
}

sub _parse_html_table {
    my $dom = shift;
    my %res;
    my $size_index = undef;
    my $dt_index = undef;
    my @ths = $dom->find('th')->each;
    for my $thi (0 .. $#ths) {
        $size_index = $thi if lc(($ths[$thi])->all_text) eq 'size';
        $dt_index = $thi if lc(($ths[$thi])->all_text) eq 'last modified';
    }
    for my $tr ($dom->find('tr')->each) {
        # try to parse header to
        my @links = $tr->find('a')->each;
        my $text;
        my $href;
        for my $link (@links) {
            $text = trim $link->text;
            $href = $link->attr->{href};

            next unless $href;
            next unless $text;
            if ('/' eq substr($href, -1)) {
                $href = basename($href) . '/';
            } else {
                $href = basename($href);
            }
            $href = uri_unescape($href);
            last if $text eq $href;
        }
        next unless $text && $text eq $href;
        my $size = undef;
        my $dt = undef;
        my @ths;
        if (defined $size_index || defined $dt_index) {
            @ths = $tr->find('td')->each;
        }
        $dt   = trim $ths[$dt_index]->text   if defined $dt_index;
        $size = trim $ths[$size_index]->text if defined $size_index;
        $res{$text} = { dt => $dt, size => $size };
    }
    return \%res;
}

sub _parse_html_ul {
    my $dom = shift;
    my $lines = $dom->all_text;
    my @links = $dom->find('a')->each;
    my %res = ();
    for my $link (@links) {
        my $text = trim $link->text;
        my $href = $link->attr->{href};

        next unless $href;
        next unless $text;
        if ('/' eq substr($href, -1)) {
            $href = basename($href) . '/';
        } else {
            $href = basename($href);
        }
        $href = uri_unescape($href);

        next unless $text eq $href;
        my $size = undef;
        my $dt = undef;
        $res{$text} = { dt => $dt, size => $size };
    }
    return \%res;
}

1;
