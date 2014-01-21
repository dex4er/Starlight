#!/usr/bin/perl

=head1 NAME

stardust - a simple and pure-Perl PSGI/Plack HTTP server with pre-forks

=head1 SYNOPSIS

$ stardust --workers=20 --max-reqs-per-child=100 app.psgi

$ stardust --port=80 --ipv6=1 app.psgi

$ stardust --port=443 --ssl=1 --ssl-key-file=file.key --ssl-cert-file=file.crt app.psgi

$ stardust --socket=/tmp/stardust.sock app.psgi

=head1 DESCRIPTION

Stardust is a standalone HTTP/1.1 server with keep-alive support. It uses
pre-forking. It is pure-Perl implementation which doesn't require any XS
package.

=head1 OPTIONS

See L<plackup> and L<Stardust> for available command line options.

=cut


use 5.008_001;

use strict;
use warnings;

our $VERSION = '0.0100';

use Plack::Runner;

sub version {
    print "Stardust $VERSION\n";
}

my $runner = Plack::Runner->new(
    server     => 'Stardust',
    env        => 'deployment',
    loader     => 'Delayed',
    version_cb => \&version,
);
$runner->parse_options(@ARGV);
$runner->run;


=head1 SEE ALSO

L<http://github.com/dex4er/Stardust>.

=head1 AUTHOR

Piotr Roszatycki <dexter@cpan.org>

=head1 LICENSE

Copyright (c) 2013-2014 Piotr Roszatycki <dexter@cpan.org>.

This is free software; you can redistribute it and/or modify it under
the same terms as perl itself.

See L<http://dev.perl.org/licenses/artistic.html>
