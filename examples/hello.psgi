#!/usr/bin/perl

# Simple PSGI application

use strict;
use warnings;

my $app = do 'mojo.pl';

use Plack::Builder;

builder {
    enable_if { $_[0]->{QUERY_STRING} =~ /foo/ } 'TrafficLog';
    enable 'Debug';
    $app;
};
