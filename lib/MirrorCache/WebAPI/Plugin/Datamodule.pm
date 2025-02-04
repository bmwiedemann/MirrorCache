# Copyright (C) 2021 SUSE LLC
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

package MirrorCache::WebAPI::Plugin::Datamodule;
use Mojo::Base 'Mojolicious::Plugin', -signatures;
use Mojo::URL;
use MirrorCache::Utils 'region_for_country';

has c => undef, weak => 1;

has [ 'route', 'route_len' ];
has [ 'metalink', 'metalink_accept' ];
has [ '_ip', '_country', '_region', '_lat', '_lng' ];
has [ '_avoid_countries' ];
has [ '_path', '_trailing_slash' ];
has [ '_query', '_query1' ];
has '_original_path';
has '_agent';
has [ '_is_secure', '_is_ipv4' ];

has root_country => ($ENV{MIRRORCACHE_ROOT_COUNTRY} ? lc($ENV{MIRRORCACHE_ROOT_COUNTRY}) : "");
has '_root_region';
has '_root_longitude' => ($ENV{MIRRORCACHE_ROOT_LONGITUDE} ? int($ENV{MIRRORCACHE_ROOT_LONGITUDE}) : 11);

my %subsidiary_urls;
my @subsidiaries;

sub register($self, $app, $args) {
    $self->route($app->mc->route);
    $self->route_len(length($self->route));
    $self->_root_region(region_for_country($self->root_country) || '');

    $app->helper( 'dm' => sub {
        return $self;
    });

    eval { #the table may be missing - no big deal
        @subsidiaries = $app->schema->resultset('Subsidiary')->all;
    };
    for my $s (@subsidiaries) {
        my $url = $s->hostname;
        $url = "http://" . $url unless 'http' eq substr($url, 0, 4);
        $url = $url . $s->uri if $s->uri;
        $subsidiary_urls{lc($s->region)} = Mojo::URL->new($url)->to_abs;
    }
}

sub reset($self, $c) {
    $self->c($c);
    $self->_ip(undef);
    $self->_country(undef);
    $self->_region(undef);
    $self->_lat(undef);
    $self->_lng(undef);
    $self->_path(undef);
    $self->_trailing_slash(undef);
    $self->_query(undef);
    $self->_query1(undef);
    $self->_original_path(undef);
    $self->_agent(undef);
    $self->_is_ipv4(undef);
    $self->_is_secure(undef);
    $self->metalink(undef);
    $self->metalink_accept(undef);

    $self->_avoid_countries(undef);
}

sub ip($self) {
    unless (defined $self->_ip) {
       $self->_ip($self->c->mmdb->client_ip);
    }
    return $self->_ip;
}

sub region($self) {
    unless (defined $self->_region) {
        $self->_init_location;
    }
    return $self->_region;
}

sub country($self) {
    unless (defined $self->_country) {
        $self->_init_location;
    }
    return $self->_country;
}

sub avoid_countries($self) {
    unless (defined $self->_country) {
        $self->_init_location;
    }
    return $self->_avoid_countries;
}

sub lat($self) {
    unless (defined $self->_lat) {
        $self->_init_location;
    }
    return $self->_lat;
}

sub lng($self) {
    unless (defined $self->_lng) {
        $self->_init_location;
    }
    return $self->_lng;
}

sub has_subsidiary($self) {
    return undef unless keys %subsidiary_urls;
    my $url = $subsidiary_urls{$self->region};
    return $url;
}

sub path($self) {
    unless (defined $self->_path) {
        $self->_init_path;
    }
    return $self->_path, $self->_trailing_slash, $self->_original_path;
}

sub trailing_slash($self) {
    unless (defined $self->_trailing_slash) {
        $self->_init_path;
    }
    return $self->_trailing_slash;
}

sub query($self) {
    unless (defined $self->_query) {
        $self->_init_path;
    }
    return $self->_query;
}

sub query1($self) {
    unless (defined $self->_query1) {
        $self->_init_path;
    }
    return $self->_query1;
}

sub path_query($self) {
    return $self->path . $self->query1;
}

sub original_path($self) {
    unless (defined $self->_trailing_slash) {
        $self->_init_path;
    }
    return $self->_original_path;
}

sub our_path($self, $path) {
    return 1 if 0 eq rindex($path, $self->route, 0);
    return 0;
}

sub agent($self) {
    unless (defined $self->_agent) {
        $self->_init_headers;
    }
    return $self->_agent;
}

sub is_secure($self) {
    unless (defined $self->_is_secure) {
        $self->_init_req;
    }
    return $self->_is_secure;
}

sub is_ipv4($self) {
    unless (defined $self->_is_ipv4) {
        $self->_init_req;
    }
    return $self->_is_ipv4;
}

sub redirect($self, $url) {
    return $self->c->redirect_to($url . $self->query1);
}

sub _init_headers($self) {
    my $headers = $self->c->req->headers;
    return unless $headers;
    $self->_agent($headers->user_agent ? $headers->user_agent : '');
    if ($headers->accept && $headers->accept =~ m/\bapplication\/metalink/) {
        $self->metalink(1);
        $self->metalink_accept(1);
    }
}

sub _init_req($self) {
    $self->_is_secure($self->c->req->is_secure? 1 : 0);
    $self->_is_ipv4(1);
    if (my $ip = $self->ip) {
        $self->_is_ipv4(0) if index($ip,':') > -1 && $ip ne '::ffff:127.0.0.1'
    }
}

sub _init_location($self) {
    my ($lat, $lng, $country, $region) = $self->c->mmdb->location($self->ip);
    $self->_lat($lat);
    $self->_lng($lng);
    my $query = $self->c->req->url->query;
    if (my $p = $query->param('COUNTRY')) {
        if (length($p) == 2 ) {
            $country = $p;
            $region = region_for_country($country);
        }
    }
    if (my $p = $query->param('REGION')) {
        if (length($p) == 2 ) {
            $region = lc($p);
        }
    }
    if (my $p = $query->param('AVOID_COUNTRY')) {
        my @avoid_countries = ();
        for my $c (split ',', $p) {
            next unless length($c) == 2;
            $c = lc($c);
            push @avoid_countries, $c;
            $country = '' if $c eq lc($country);
        }
        $self->_avoid_countries(\@avoid_countries);
    }
    $self->_country($country // '');
    $self->_region($region // '');
}

sub _init_path($self) {
    my $url = $self->c->req->url;
    if ($url->query) {
        $self->_query($url->query);
        $self->_query1('?' . $url->query);
    } else {
        $self->_query('');
        $self->_query1('');
    }

    my $reqpath = $url->path;
    my $path = Mojo::Util::url_unescape(substr($reqpath, $self->route_len));
    $path = '/' unless $path;

    my $trailing_slash = '';
    if($path ne '/' && '/' eq substr($path, -1)) {
        $trailing_slash = '/';
        $path = substr($path, 0, -1);
    }
    $self->_original_path($path);
    my @c = reverse split m@/@, $path;
    my @c_new;
    while (@c) {
        my $component = shift @c;
        next unless length($component);
        if ($component eq '.') { next; }
        if ($component eq '..') { shift @c; next }
        push @c_new, $component;
    }
    $path = '/'.join('/', reverse @c_new);
    if(!$trailing_slash && ((my $pos = length($path)-length('.metalink')) > 1)) {
        if ('.metalink' eq substr($path,$pos)) {
            $self->metalink(1);
            $path = substr($path,0,$pos);
        }
    }
    $self->_path($path);
    $self->_trailing_slash($trailing_slash);
    $self->agent; # parse headers
}

sub root_is_hit($self) {
    return 1 if $self->_root_region eq $self->region;
    return 0;
}

sub root_is_better($self, $region, $lng) {
    if ($self->_root_region && $region && $self->lng && $self->_root_longitude && $region eq $self->_root_region) {
        # simly check if root is closer to the client by longitude
        return 1 if abs( $self->_root_longitude - $self->lng ) < abs( $lng - $self->lng );
    }
    return 0;
}

1;
