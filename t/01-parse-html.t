use Carp;
use Test::More;
use Test::Exception;
use Data::Dumper;
use Mojo::DOM;
use warnings;
use strict;

BEGIN { use_ok('MirrorCache::WebAPI::Plugin::RootRemote'); }



subtest 'parse_html_table' => sub {
    my $table = <<'HTML';
<table><tr><th><img src="/theme/icons/blank.svg" alt="[ICO]" width="16" height="16" /></th><th><a href="?C=N;O=D">Name</a></th><th><a href="?C=M;O=A">Last modified</a></th><th><a href="?C=S;O=A">Size</a></th><th>Metadata</th></tr><tr><th colspan="5"><hr /></th></tr>
<tr><td valign="top"><a href="/repositories/Apache:/Test/openSUSE_Leap_15.2/"><img src="/theme/icons/up.svg" alt="[DIR]" width="16" height="16" /></a></td><td><a href="/repositories/Apache:/Test/openSUSE_Leap_15.2/">Parent Directory</a></td><td>&nbsp;</td><td align="right">  - </td><td>&nbsp;</td></tr>
<tr><td valign="top"><a href="apache-rpm-macros-20201124-lp152.41.1.x86_64.rpm"><img src="/theme/icons/package.svg" alt="[   ]" width="16" height="16" /></a></td><td><a href="apache-rpm-macros-20201124-lp152.41.1.x86_64.rpm">apache-rpm-macros-20201124-lp152.41.1.x86_64.rpm</a></td><td align="right">08-Dec-2020 14:02  </td><td align="right"> 10K </td><td><a href="apache-rpm-macros-20201124-lp152.41.1.x86_64.rpm.mirrorlist">Details</a></td></tr>
<tr><td valign="top"><a href="apache-rpm-macros-control-20151110-lp152.12.1.x86_64.rpm"><img src="/theme/icons/package.svg" alt="[   ]" width="16" height="16" /></a></td><td><a href="apache-rpm-macros-control-20151110-lp152.12.1.x86_64.rpm">apache-rpm-macros-control-20151110-lp152.12.1.x86_64.rpm</a></td><td align="right">13-Jul-2020 09:09  </td><td align="right">8.1K </td><td><a href="apache-rpm-macros-control-20151110-lp152.12.1.x86_64.rpm.mirrorlist">Details</a></td></tr>
<tr><td valign="top"><a href="perl-Net-SSLeay-1.88-lp152.52.2.x86_64.rpm"><img src="/theme/icons/package.svg" alt="[   ]" width="16" height="16" /></a></td><td><a href="perl-Net-SSLeay-1.88-lp152.52.2.x86_64.rpm">perl-Net-SSLeay-1.88-lp152.52.2.x86_64.rpm</a></td><td align="right">01-Nov-2020 11:37  </td><td align="right">354K </td><td><a href="perl-Net-SSLeay-1.88-lp152.52.2.x86_64.rpm.mirrorlist">Details</a></td></tr>
<tr><td valign="top"><a href="softhsm-2.5.0-lp152.3.2.x86_64.rpm"><img src="/theme/icons/package.svg" alt="[   ]" width="16" height="16" /></a></td><td><a href="softhsm-2.5.0-lp152.3.2.x86_64.rpm">softhsm-2.5.0-lp152.3.2.x86_64.rpm</a></td><td align="right">01-Nov-2020 11:39  </td><td align="right">370K </td><td><a href="softhsm-2.5.0-lp152.3.2.x86_64.rpm.mirrorlist">Details</a></td></tr>
<tr><td valign="top"><a href="softhsm-devel-2.5.0-lp152.3.2.x86_64.rpm"><img src="/theme/icons/package.svg" alt="[   ]" width="16" height="16" /></a></td><td><a href="softhsm-devel-2.5.0-lp152.3.2.x86_64.rpm">softhsm-devel-2.5.0-lp152.3.2.x86_64.rpm</a></td><td align="right">01-Nov-2020 11:39  </td><td align="right"> 21K </td><td><a href="softhsm-devel-2.5.0-lp152.3.2.x86_64.rpm.mirrorlist">Details</a></td></tr>
<tr><th colspan="5"><hr /></th></tr>
</table>
HTML

    my $res = MirrorCache::WebAPI::Plugin::RootRemote::_parse_html_table(Mojo::DOM->new($table));
    my %res = %$res;

    is(scalar(keys %res), 5, 'Correct number of elements');
    return undef unless scalar(keys %res) == 5;
    is($res{'apache-rpm-macros-20201124-lp152.41.1.x86_64.rpm'}{'dt'}, '08-Dec-2020 14:02');
    is($res{'apache-rpm-macros-20201124-lp152.41.1.x86_64.rpm'}{'size'}, '10K');
    is($res{'apache-rpm-macros-control-20151110-lp152.12.1.x86_64.rpm'}{'dt'}, '13-Jul-2020 09:09');
    is($res{'apache-rpm-macros-control-20151110-lp152.12.1.x86_64.rpm'}{'size'}, '8.1K');
    is($res{'perl-Net-SSLeay-1.88-lp152.52.2.x86_64.rpm'}{dt}, '01-Nov-2020 11:37');
    is($res{'perl-Net-SSLeay-1.88-lp152.52.2.x86_64.rpm'}{size}, '354K');
    is($res{'softhsm-2.5.0-lp152.3.2.x86_64.rpm'}{dt}, '01-Nov-2020 11:39');
    is($res{'softhsm-2.5.0-lp152.3.2.x86_64.rpm'}{size}, '370K');
    is($res{'softhsm-devel-2.5.0-lp152.3.2.x86_64.rpm'}{dt}, '01-Nov-2020 11:39');
    is($res{'softhsm-devel-2.5.0-lp152.3.2.x86_64.rpm'}{size}, '21K');
};

subtest 'parse_html_ul' => sub {
    my $ul = <<'HTML';
<li><a href="/"> Parent Directory</a></li>
<li><a href="file1.dat"> file1.dat</a></li>
<li><a href="file2.dat"> file2.dat</a></li>
<li><a href="file3.dat"> file3.dat</a></li>
<li><a href="file4.dat"> file4.dat</a></li>
<li><a href="./file:4.dat"> file:4.dat</a></li>
<li><a href="folder11/"> folder11/</a></li>
HTML

    my $res = MirrorCache::WebAPI::Plugin::RootRemote::_parse_html_ul(Mojo::DOM->new($ul));
    my %res = %$res;

    is(scalar(keys %res), 6, 'Correct number of elements');
    return undef unless scalar(keys %res) == 6;
    ok($res{'file1.dat'});
    ok($res{'file2.dat'});
    ok($res{'file3.dat'});
    ok($res{'file4.dat'});
    ok($res{'file:4.dat'});
    ok($res{'folder11/'});
};

subtest 'parse_html_pre' => sub {
    my $pre = <<'HTML';
      <a href="?C=N;O=D">Name</a>                    <a href="?C=M;O=A">Last modified</a>      <a href="?C=S;O=A">Size</a>  <a href="?C=D;O=A">Description</a><hr>      <a href="/">Parent Directory</a>                             -   
      <a href="file1.dat">file1.dat</a>               2020-12-14 15:04    2   
      <a href="file2.dat">file2.dat</a>               2020-12-14 15:04    4   
      <a href="file3.dat">file3.dat</a>               2020-12-14 15:04    6   
      <a href="file4.dat">file4.dat</a>               2020-12-14 15:04    8   
      <a href="./file:4.dat">file:4.dat</a>              2020-12-14 15:04    8   
      <a href="folder11/">folder11/</a>               2020-12-14 15:04    -   
<hr>
HTML
    my $res = MirrorCache::WebAPI::Plugin::RootRemote::_parse_html_pre(Mojo::DOM->new($pre));
    my %res = %$res;

    is(scalar(keys %res), 6, 'Correct number of elements');
    return undef unless scalar(keys %res) == 6;
    is($res{'file1.dat'}{'dt'}, '2020-12-14 15:04');
    is($res{'file1.dat'}{'size'}, 2);
    is($res{'file2.dat'}{'dt'}, '2020-12-14 15:04');
    is($res{'file2.dat'}{'size'}, 4);
    is($res{'file3.dat'}{'dt'}, '2020-12-14 15:04');
    is($res{'file3.dat'}{'size'}, 6);
    is($res{'file4.dat'}{'dt'}, '2020-12-14 15:04');
    is($res{'file4.dat'}{'size'}, 8);
    is($res{'file:4.dat'}{'dt'}, '2020-12-14 15:04');
    is($res{'file:4.dat'}{'size'}, 8);
    is($res{'folder11/'}{'dt'}, '2020-12-14 15:04');
    is($res{'folder11/'}{'size'}, '-');
};


done_testing();

