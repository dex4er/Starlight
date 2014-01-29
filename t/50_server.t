#!/usr/bin/perl

use strict;
use warnings;

BEGIN { delete $ENV{http_proxy} };

use HTTP::Tiny;
use Test::TCP;
use Test::More;

use Starlight::Server;

test_tcp(
    client => sub {
        my $port = shift;
        sleep 1;
        my $ua = HTTP::Tiny->new;
        my $res = $ua->get("http://localhost:$port/");
        ok $res->{success};
        like $res->{headers}{server}, qr/Starlight/;
        like $res->{content}, qr/Hello/;
    },
    server => sub {
        my $port = shift;
        Starlight::Server->new(
            host     => 'localhost',
            port     => $port,
        )->run(
            sub { [ 200, [], ["Hello world\n"] ] },
        );
    }
);

done_testing;
