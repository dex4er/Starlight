#!/usr/bin/perl

use strict;
use warnings;

BEGIN { delete $ENV{http_proxy} };

use Test::More;
use Plack::Test::Suite;

push @Plack::Test::Suite::TEST,
    [
        'sleep',
        sub {
            sleep 1;
            pass;
        },
        sub {
            # nothing
        },
    ];

Plack::Test::Suite->run_server_tests('Stardust');
done_testing();

