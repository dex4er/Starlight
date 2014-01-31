#!/usr/bin/perl

use strict;
use warnings;

BEGIN { delete $ENV{http_proxy} };

use HTTP::Tiny;
use Test::TCP;
use Test::More;
use FindBin;

use Starlight::Server;

if ($^O eq 'MSWin32' and $] >= 5.016 and $] < 5.019005 and not $ENV{PERL_TEST_BROKEN}) {
    plan skip_all => 'Perl with bug RT#119003 on MSWin32';
    exit 0;
}

if (not eval { require IO::Socket::SSL; }) {
    plan skip_all => 'IO::Socket::SSL required';
    exit 0;
}

my $ca_crt     = "$FindBin::Bin/../examples/ca.crt";
my $server_crt = "$FindBin::Bin/../examples/localhost.crt";
my $server_key = "$FindBin::Bin/../examples/localhost.key";

my $body       = 'x'x(32*1024); # > 16KB

test_tcp(
    client => sub {
        my $port = shift;
        sleep 1;
        my $ua = HTTP::Tiny->new(
            verify_SSL => 1,
            SSL_options => {
                SSL_ca_file   => $ca_crt,
                SSL_cert_file => $server_crt,
                SSL_key_file  => $server_key,
           }
        );
        my $res = $ua->get("https://localhost:$port/");
        ok $res->{success};
        like $res->{headers}{server}, qr/Starlight/;
        like $res->{content}, qr/xxxxxxxxxx/;
        is length $res->{content}, length $body;
        sleep 1;
    },
    server => sub {
        my $port = shift;
        Starlight::Server->new(
            host          => 'localhost',
            port          => $port,
            ssl           => 1,
            ssl_key_file  => $server_key,
            ssl_cert_file => $server_crt,
        )->run(
            sub { [ 200, [], [$body] ] },
        );
    }
);

done_testing;
