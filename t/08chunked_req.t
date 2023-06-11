#!/usr/bin/perl

use strict;
use warnings;

BEGIN { delete $ENV{http_proxy} }

# workaround for HTTP::Tiny + Test::TCP
BEGIN { $INC{'threads.pm'} = 0 }
sub threads::tid { }

use Digest::MD5;
use File::ShareDir;
use File::Temp;
use HTTP::Tiny;
use Plack::Loader;
use Test::More;
use Test::TCP;

if ($^O eq 'MSWin32' and not $ENV{PERL_TEST_BROKEN}) {
    plan skip_all => 'Perl with bug RT#119003 on MSWin32';
    exit 0;
}

if ($^O eq 'cygwin' and not $ENV{PERL_TEST_BROKEN}) {
    plan skip_all => 'Broken on cygwin';
    exit 0;
}

my ($fh, $filename) = File::Temp::tempfile(UNLINK => 1);
ok $fh, '$fh';
print $fh 'A' x 100_000;
close $fh;

test_tcp(
    client => sub {
        my $port = shift;
        sleep 2;

        my $status = open my $fh, '<:raw', $filename;
        ok $status, 'open';

        local $/ = \1024;

        my $ua  = HTTP::Tiny->new(timeout => 10);
        my $res = $ua->post("http://127.0.0.1:$port/", { content => sub { scalar <$fh> } });

        ok $res->{success}, 'success';
        is $res->{status},                        '200',                              'status';
        is $res->{reason},                        'OK',                               'reason';
        is $res->{headers}{'x-content-length'},   100_000,                            'length';
        is Digest::MD5::md5_hex($res->{content}), '5793f7e3037448b250ae716b43ece2c2', 'content';
        like $res->{content}, qr/^A{25000}A{25000}A{25000}A{25000}$/, 'content';

        sleep 1;
    },
    server => sub {
        my $port   = shift;
        my $loader = Plack::Loader->load(
            'Starlight',
            quiet       => 1,
            port        => $port,
            max_workers => 5,
        );
        $loader->run(
            sub {
                my $env = shift;
                my $body;
                eval {
                    my $clen = $env->{CONTENT_LENGTH};
                    while ($clen > 0) {
                        $env->{'psgi.input'}->read(my $buf, $clen) or last;
                        $clen -= length $buf;
                        $body .= $buf;
                    }
                    1;
                } or $body = $@;
                return [200, ['Content-Type', 'text/plain', 'X-Content-Length', $env->{CONTENT_LENGTH}], [$body]];
            }
        );
    },
);

done_testing;
