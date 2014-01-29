#!/usr/bin/perl

use strict;
use warnings;

BEGIN { delete $ENV{http_proxy} };

use HTTP::Tiny;
use Test::TCP;
use Test::More;
use FindBin;

use Starlight::Server;

if (not eval { require IO::Socket::SSL; }) {
    plan skip_all => 'IO::Socket::SSL required';
    exit 0;
}

my $ca_crt     = "$FindBin::Bin/../examples/ca.crt";
my $server_crt = "$FindBin::Bin/../examples/localhost.crt";
my $server_key = "$FindBin::Bin/../examples/localhost.key";

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
        is $res->{content}, 'https';
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
            sub { [ 200, [], [$_[0]->{'psgi.url_scheme'}] ] },
        );
    }
);

done_testing;
