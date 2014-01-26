#!/usr/bin/perl

use strict;
use warnings;

BEGIN { delete $ENV{http_proxy} };

use HTTP::Request::Common;
use Plack::Test;
use Test::More;

if ($^O eq 'MSWin32' and $] >= 5.016 and $] < 5.019005 and not $ENV{PERL_TEST_BROKEN}) {
    plan skip_all => 'Perl with bug RT#119003 on Windows';
    exit 0;
}

$Plack::Test::Impl = 'Server';
$ENV{PLACK_SERVER} = 'Starlight';

test_psgi
    app => sub {
        my $env = shift;
        unless (my $pid = fork) {
            die "fork failed:$!"
                unless defined $pid;
            # child process
            sleep 1;
            kill 'TERM', getppid();
            exit 0;
        }
        sleep 5;
        return [ 200, [ 'Content-Type' => 'text/plain' ], [ "hello world" ] ];
    },
    client => sub {
        my $cb = shift;
        my $res = $cb->(GET "/");
        is $res->content, "hello world";
    };

done_testing;
