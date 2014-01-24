#!/usr/bin/perl

=head1 NAME

starlight - a light and pure-Perl PSGI/Plack HTTP server with pre-forks

=head1 SYNOPSIS

  $ starlight --workers=20 --max-reqs-per-child=100 app.psgi

  $ starlight --port=80 --ipv6=1 app.psgi

  $ starlight --port=443 --ssl=1 --ssl-key-file=file.key --ssl-cert-file=file.crt app.psgi

  $ starlight --socket=/tmp/starlight.sock app.psgi

=head1 DESCRIPTION

Starlight is a standalone HTTP/1.1 server with keep-alive support. It uses
pre-forking. It is pure-Perl implementation which doesn't require any XS
package.

=for readme stop

=cut


use 5.008_001;

use strict;
use warnings;

our $VERSION = '0.0100';

use Plack::Runner;

sub version {
    print "Starlight $VERSION\n";
}

my $runner = Plack::Runner->new(
    server     => 'Starlight',
    env        => 'deployment',
    loader     => 'Delayed',
    version_cb => \&version,
);
$runner->parse_options(@ARGV);
$runner->run;


=head1 OPTIONS

In addition to the options supported by L<plackup>, starlight accepts following
options(s).

=over

=item --max-workers=#

number of worker processes (default: 10)

=item --timeout=#

seconds until timeout (default: 300)

=item --keepalive-timeout=#

timeout for persistent connections (default: 2)

=item --max-keepalive-reqs=#

max. number of requests allowed per single persistent connection.  If set to
one, persistent connections are disabled (default: 1)

=item --max-reqs-per-child=#

max. number of requests to be handled before a worker process exits (default:
1000)

=item --min-reqs-per-child=#

if set, randomizes the number of requests handled by a single worker process
between the value and that supplied by C<--max-reqs-per-chlid> (default: none)

=item --spawn-interval=#

if set, worker processes will not be spawned more than once than every given
seconds.  Also, when SIGHUP is being received, no more than one worker
processes will be collected every given seconds.  This feature is useful for
doing a "slow-restart". (default: none)

=item --main-process-delay=#

the Starlight does not synchronize its processes and it requires a small delay in
main process so it doesn't consume all CPU. (default: 0.1)

=item --ssl=#

enables SSL support. The L<IO::Socket::SSL> module is required. (default: 0)

=item --ssl-key-file=#

specifies the path to SSL key file. (default: none)

=item --ssl-cert-file=#

specifies the path to SSL certificate file. (default: none)

=item --ipv6=#

enables IPv6 support. The L<IO::Socket::IP> module is required. (default: 0)

=item --socket=#

enables UNIX socket support. The L<IO::Socket::UNIX> module is required. The
socket file have to be not yet created. The first character C<@> or C<\0> in
the socket file name means that abstract socket address will be created.
(default: none)

=back

=for readme continue

=head1 NOTES

Starlight was started as a fork of L<Thrall> server which is a fork of
L<Starlet> server. It has almost the same code as L<Thrall> and L<Starlet> and
it was adapted to doesn't use any other modules than L<Plack>.

=head1 SEE ALSO

L<Starlight>,
L<Thrall>,
L<Starlet>,
L<Starman>

=head1 LIMITATIONS

Perl on Windows systems (MSWin32 and cygwin) emulates fork and waitpid functions
and uses threads internally. See L<perlfork> (MSWin32) and L<perlcygwin>
(cygwin) for details and limitations.

It might be better option to use on this system the server with explicit threads
implementation, i.e. L<Thrall>.

For Cygwin the C<perl-libwin32> package is highly recommended, because of
L<Win32::Process> module which helps to terminate stalled worker processes.

=head1 BUGS

There is a problem with Perl threads implementation which occurs on Windows
systems (MSWin32). Cygwin version seems to be correct.

Some requests can fail with message:

  failed to set socket to nonblocking mode:An operation was attempted on
  something that is not a socket.

or

  Bad file descriptor at (eval 24) line 4.

This problem was introduced in Perl 5.16 and fixed in Perl 5.19.5.

See L<https://rt.perl.org/rt3/Public/Bug/Display.html?id=119003> and
L<https://github.com/dex4er/Thrall/issues/5> for more information about this
issue.

Harakiri mode fails with message:

  Attempt to free unreferenced scalar: SV 0x293a76c, Perl interpreter:
  0x22dcc0c at lib/Plack/Handler/Starlight.pm line 140.

See L<https://rt.perl.org/Public/Bug/Display.html?id=40565> and
L<https://github.com/dex4er/Starlight/issues/1> for more information about this
issue.

=head2 Reporting

If you find the bug or want to implement new features, please report it at
L<https://github.com/dex4er/Starlight/issues>

The code repository is available at
L<http://github.com/dex4er/Starlight>

=head1 AUTHORS

Piotr Roszatycki <dexter@cpan.org>

Based on Thrall by:

Piotr Roszatycki <dexter@cpan.org>

Based on Starlet by:

Kazuho Oku

miyagawa

kazeburo

Some code based on Plack:

Tatsuhiko Miyagawa

=head1 LICENSE

Copyright (c) 2013-2014 Piotr Roszatycki <dexter@cpan.org>.

This is free software; you can redistribute it and/or modify it under
the same terms as perl itself.

See L<http://dev.perl.org/licenses/artistic.html>
