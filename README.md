[![Build Status](https://travis-ci.org/dex4er/Stardust.png?branch=master)](https://travis-ci.org/dex4er/Stardust)

# NAME

Stardust - a simple and pure-Perl PSGI/Plack HTTP server with pre-forks

# SYNOPSIS

    $ plackup -s Stardust --port=80 [options] your-app.psgi

    $ plackup -s Stardust --port=443 --ssl=1 --ssl-key-file=file.key --ssl-cert-file=file.crt [options] your-app.psgi

    $ plackup -s Stardust --port=80 --ipv6 [options] your-app.psgi

    $ plackup -s Stardust --socket=/tmp/stardust.sock [options] your-app.psgi

    $ stardust your-app.psgi

# DESCRIPTION

Stardust is a standalone HTTP/1.1 server with keep-alive support. It uses
pre-forking. It is pure-Perl implementation which doesn't require any XS
package.

# COMMAND LINE OPTIONS

In addition to the options supported by [plackup](https://metacpan.org/pod/plackup), Stardust accepts following
options(s).

- \--max-workers=\#

    number of worker processes (default: 10)

- \--timeout=\#

    seconds until timeout (default: 300)

- \--keepalive-timeout=\#

    timeout for persistent connections (default: 2)

- \--max-keepalive-reqs=\#

    max. number of requests allowed per single persistent connection.  If set to
    one, persistent connections are disabled (default: 1)

- \--max-reqs-per-child=\#

    max. number of requests to be handled before a worker process exits (default:
    1000)

- \--min-reqs-per-child=\#

    if set, randomizes the number of requests handled by a single worker process
    between the value and that supplied by `--max-reqs-per-chlid` (default: none)

- \--spawn-interval=\#

    if set, worker processes will not be spawned more than once than every given
    seconds.  Also, when SIGHUP is being received, no more than one worker
    processes will be collected every given seconds.  This feature is useful for
    doing a "slow-restart". (default: none)

- \--main-process-delay=\#

    the Stardust does not synchronize its processes and it requires a small delay in
    main process so it doesn't consume all CPU. (default: 0.1)

- \--ssl=\#

    enables SSL support. The [IO::Socket::SSL](https://metacpan.org/pod/IO::Socket::SSL) module is required. (default: 0)

- \--ssl-key-file=\#

    specifies the path to SSL key file. (default: none)

- \--ssl-cert-file=\#

    specifies the path to SSL certificate file. (default: none)

- \--ipv6=\#

    enables IPv6 support. The [IO::Socket::IP](https://metacpan.org/pod/IO::Socket::IP) module is required. (default: 0)

- \--socket=\#

    enables UNIX socket support. The [IO::Socket::UNIX](https://metacpan.org/pod/IO::Socket::UNIX) module is required. The
    socket file have to be not yet created. The first character `@` or `\0` in
    the socket file name means that abstract socket address will be created.
    (default: none)

# NOTES

Stardust was started as a fork of [Thrall](https://metacpan.org/pod/Thrall) server which is a fork of
[Starlet](https://metacpan.org/pod/Starlet) server. It has almost the same code as [Thrall](https://metacpan.org/pod/Thrall) and [Starlet](https://metacpan.org/pod/Starlet) and
it was adapted to doesn't use any other modules than [Plack](https://metacpan.org/pod/Plack).

# SEE ALSO

[stardust](https://metacpan.org/pod/stardust),
[Thrall](https://metacpan.org/pod/Thrall),
[Starlet](https://metacpan.org/pod/Starlet),
[Starman](https://metacpan.org/pod/Starman)

# LIMITATIONS

Perl on Windows systems (MSWin32 and cygwin) emulates fork and waitpid functions
and uses threads internally. See [perlfork](https://metacpan.org/pod/perlfork) (MSWin32) and [perlcygwin](https://metacpan.org/pod/perlcygwin)
(cygwin) for details and limitations.

It might be better option to use on this system the server with explicit threads
implementation, i.e. [Thrall](https://metacpan.org/pod/Thrall).

For Cygwin the `perl-libwin32` package is highly recommended, because of
[Win32::Process](https://metacpan.org/pod/Win32::Process) module which helps to terminate stalled worker processes.

# BUGS

There is a problem with Perl threads implementation which occurs on Windows
systems (MSWin32). Cygwin version seems to be correct.

Some requests can fail with message:

    failed to set socket to nonblocking mode:An operation was attempted on
    something that is not a socket.

or

    Bad file descriptor at (eval 24) line 4.

This problem was introduced in Perl 5.16 and fixed in Perl 5.19.5.

See [https://rt.perl.org/rt3/Public/Bug/Display.html?id=119003](https://rt.perl.org/rt3/Public/Bug/Display.html?id=119003) and
[https://github.com/dex4er/Thrall/issues/5](https://github.com/dex4er/Thrall/issues/5) for more information about this
issue.

Harakiri mode fails with message:

    Attempt to free unreferenced scalar: SV 0x293a76c, Perl interpreter:
    0x22dcc0c at lib/Plack/Handler/Stardust.pm line 140.

See [https://rt.perl.org/Public/Bug/Display.html?id=40565](https://rt.perl.org/Public/Bug/Display.html?id=40565) and
[https://github.com/dex4er/Stardust/issues/1](https://github.com/dex4er/Stardust/issues/1) for more information about this
issue.

## Reporting

If you find the bug or want to implement new features, please report it at
[https://github.com/dex4er/Stardust/issues](https://github.com/dex4er/Stardust/issues)

The code repository is available at
[http://github.com/dex4er/Stardust](http://github.com/dex4er/Stardust)

# AUTHORS

Piotr Roszatycki <dexter@cpan.org>

Based on Thrall by:

Piotr Roszatycki <dexter@cpan.org>

Based on Starlet by:

Kazuho Oku

miyagawa

kazeburo

Some code based on Plack:

Tatsuhiko Miyagawa

# LICENSE

Copyright (c) 2013-2014 Piotr Roszatycki <dexter@cpan.org>.

This is free software; you can redistribute it and/or modify it under
the same terms as perl itself.

See [http://dev.perl.org/licenses/artistic.html](http://dev.perl.org/licenses/artistic.html)
