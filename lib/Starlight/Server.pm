package Starlight::Server;

use strict;
use warnings;

our $VERSION = '0.0100';

use Config;

use Carp ();
use Plack;
use Plack::HTTPParser qw( parse_http_request );
use IO::Socket::INET;
use HTTP::Date;
use HTTP::Status;
use List::Util qw(max sum);
use Plack::Util;
use Plack::TempBuffer;
use POSIX qw(EINTR EAGAIN EWOULDBLOCK);
use Socket qw(IPPROTO_TCP TCP_NODELAY);

use Try::Tiny;
use Time::HiRes qw(time);

use constant DEBUG            => $ENV{PERL_STARLIGHT_DEBUG};
use constant CHUNKSIZE        => 64 * 1024;
use constant MAX_REQUEST_SIZE => 131072;

use constant HAS_INET6        => eval { AF_INET6 && socket my $ipv6_socket, AF_INET6, SOCK_DGRAM, 0 };

my $null_io = do { open my $io, "<", \""; $io }; #"

sub new {
    my($class, %args) = @_;

    my $self = bless {
        host                 => $args{host},
        port                 => $args{port},
        socket               => $args{socket},
        listen               => $args{listen},
        listen_sock          => $args{listen_sock},
        timeout              => $args{timeout} || 300,
        keepalive_timeout    => $args{keepalive_timeout} || 2,
        max_keepalive_reqs   => $args{max_keepalive_reqs} || 1,
        server_software      => $args{server_software} || "Starlight/$VERSION ($^O)",
        server_ready         => $args{server_ready} || sub {},
        ssl                  => $args{ssl},
        ipv6                 => $args{ipv6},
        ssl_key_file         => $args{ssl_key_file},
        ssl_cert_file        => $args{ssl_cert_file},
        min_reqs_per_child   => (
            defined $args{min_reqs_per_child}
                ? $args{min_reqs_per_child} : undef,
        ),
        max_reqs_per_child   => (
            $args{max_reqs_per_child} || $args{max_requests} || 1000,
        ),
        spawn_interval       => $args{spawn_interval} || 0,
        err_respawn_interval => (
            defined $args{err_respawn_interval}
                ? $args{err_respawn_interval} : undef,
        ),
        main_process_delay   => $args{main_process_delay} || 0.1,
        is_multithread       => Plack::Util::FALSE,
        is_multiprocess      => Plack::Util::FALSE,
        _using_defer_accept  => undef,
        _unlink              => [],
        _sigint              => 'INT',
    }, $class;

    # Windows 7 and previous have bad SIGINT handling
    if ($^O eq 'MSWin32') {
        require Win32;
        my @v = Win32::GetOSVersion();
        if ($v[1]*1000 + $v[2] < 6_002) {
            $self->{_sigint} = 'TERM';
        }
    };

    if ($args{max_workers} && $args{max_workers} > 1) {
        Carp::carp(
            "Forking in $class is deprecated. Falling back to the single process mode. ",
            "If you need more workers, use Starman, Starlet or Starlight instead and run like `plackup -s Starlight`",
        );
    }

    $self;
}

sub run {
    my($self, $app) = @_;
    $self->setup_listener();
    $self->accept_loop($app);
}

sub prepare_socket_class {
    my($self, $args) = @_;

    if ($self->{socket} and ($self->{ssl} or $self->{ipv6})) {
        Carp::croak("UNIX socket and either SSL or IPv6 are not supported at the same time. Choose one.");
    }

    if ($self->{ssl} and $self->{ipv6}) {
        Carp::croak("SSL and IPv6 are not supported at the same time (yet). Choose one.");
    }

    if ($self->{socket}) {
        try { require IO::Socket::UNIX; 1 }
            or Carp::croak("UNIX socket suport requires IO::Socket::UNIX");
        $args->{Local} =~ s/^@/\0/; # abstract socket address
        return "IO::Socket::UNIX";
    } elsif ($self->{ssl}) {
        try { require IO::Socket::SSL; 1 }
            or Carp::croak("SSL suport requires IO::Socket::SSL");
        $args->{SSL_key_file}  = $self->{ssl_key_file};
        $args->{SSL_cert_file} = $self->{ssl_cert_file};
        return "IO::Socket::SSL";
    } elsif ($self->{ipv6}) {
        try { require IO::Socket::IP; 1 }
            or Carp::croak("IPv6 support requires IO::Socket::IP");
        $self->{host}      ||= '::';
        $args->{LocalAddr} ||= '::';
        return "IO::Socket::IP";
    }

    return "IO::Socket::INET";
}

sub setup_listener {
    my ($self) = @_;

    my %args = $self->{socket} ? (
        Listen    => Socket::SOMAXCONN,
        Local     => $self->{socket},
    ) : (
        Listen    => Socket::SOMAXCONN,
        LocalPort => $self->{port} || 5000,
        LocalAddr => $self->{host} || 0,
        Proto     => 'tcp',
        ReuseAddr => 1,
    );

    my $class = $self->prepare_socket_class(\%args);
    $self->{listen_sock} ||= $class->new(%args)
        or die sprintf "failed to listen to %s: $!", $self->{socket}
            ? "socket $self->{socket}" : "port $self->{port}";

    my $family = Socket::sockaddr_family(getsockname($self->{listen_sock}));
    $self->{_listen_sock_is_unix} = $family == AF_UNIX;
    $self->{_listen_sock_is_tcp}  = $family != AF_UNIX;

    # set defer accept
    if ($^O eq 'linux' && $self->{_listen_sock_is_tcp}) {
        setsockopt($self->{listen_sock}, IPPROTO_TCP, 9, 1)
            and $self->{_using_defer_accept} = 1;
    }

    if ($self->{_listen_sock_is_unix} && not $args{Local} =~ /^\0/) {
        push @{$self->{_unlink}}, $args{Local};
    }

    $self->{server_ready}->({ %$self, proto => $self->{ssl} ? 'https' : 'http' });
}

sub accept_loop {
    # TODO handle $max_reqs_per_child
    my($self, $app, $max_reqs_per_child) = @_;
    my $proc_req_count = 0;

    $self->{can_exit} = 1;
    my $is_keepalive = 0;
    my $sigint = $self->{_sigint};
    local $SIG{$sigint} = local $SIG{TERM} = sub {
        my ($sig) = @_;
        warn "*** SIG$sig received in process $$" if DEBUG;
        exit 0 if $self->{can_exit};
        $self->{term_received}++;
        exit 0
            if ($is_keepalive && $self->{can_exit}) || $self->{term_received} > 1;
        # warn "server termination delayed while handling current HTTP request";
    };

    local $SIG{PIPE} = 'IGNORE';

    while (! defined $max_reqs_per_child || $proc_req_count < $max_reqs_per_child) {
        if (my ($conn,$peer) = $self->{listen_sock}->accept) {
            $self->{_is_deferred_accept} = $self->{_using_defer_accept};
            $conn->blocking(0)
                or die "failed to set socket to nonblocking mode:$!";
            my ($peerport, $peerhost, $peeraddr) = (0, undef, undef);
            if ($self->{_listen_sock_is_tcp}) {
                $conn->setsockopt(IPPROTO_TCP, TCP_NODELAY, 1)
                    or die "setsockopt(TCP_NODELAY) failed:$!";
                local $@;
                if (HAS_INET6 && Socket::sockaddr_family(getsockname($conn)) == AF_INET6) {
                    ($peerport, $peerhost) = Socket::unpack_sockaddr_in6($peer);
                    $peeraddr = Socket::inet_ntop(AF_INET6, $peerhost);
                } else {
                    ($peerport, $peerhost) = Socket::unpack_sockaddr_in($peer);
                    $peeraddr = Socket::inet_ntoa($peerhost);
                }
            }
            my $req_count = 0;
            my $pipelined_buf = '';
            while (1) {
                ++$req_count;
                ++$proc_req_count;
                my $env = {
                    SERVER_PORT => $self->{port} || 0,
                    SERVER_NAME => $self->{host} || '*',
                    SCRIPT_NAME => '',
                    REMOTE_ADDR => $peeraddr,
                    REMOTE_PORT => $peerport,
                    'psgi.version' => [ 1, 1 ],
                    'psgi.errors'  => *STDERR,
                    'psgi.url_scheme'   => $self->{ssl} ? 'https' : 'http',
                    'psgi.run_once'     => Plack::Util::FALSE,
                    'psgi.multithread'  => $self->{is_multithread},
                    'psgi.multiprocess' => $self->{is_multiprocess},
                    'psgi.streaming'    => Plack::Util::TRUE,
                    'psgi.nonblocking'  => Plack::Util::FALSE,
                    'psgix.input.buffered' => Plack::Util::TRUE,
                    'psgix.io'          => $conn,
                    'psgix.harakiri'    => Plack::Util::TRUE,
                };

                my $may_keepalive = $req_count < $self->{max_keepalive_reqs};
                if ($may_keepalive && $max_reqs_per_child && $proc_req_count >= $max_reqs_per_child) {
                    $may_keepalive = undef;
                }
                $may_keepalive = 1 if length $pipelined_buf;
                my $keepalive;
                ($keepalive, $pipelined_buf) = $self->handle_connection($env, $conn, $app,
                                                                        $may_keepalive, $req_count != 1, $pipelined_buf);

                if ($env->{'psgix.harakiri.commit'}) {
                    $conn->close;
                    return;
                }
                last unless $keepalive;
                # TODO add special cases for clients with broken keep-alive support, as well as disabling keep-alive for HTTP/1.0 proxies
            }
            $conn->close;
        }
    }
}

my $bad_response = [ 400, [ 'Content-Type' => 'text/plain', 'Connection' => 'close' ], [ 'Bad Request' ] ];
sub handle_connection {
    my($self, $env, $conn, $app, $use_keepalive, $is_keepalive, $prebuf) = @_;

    my $buf = '';
    my $pipelined_buf='';
    my $res = $bad_response;

    local $self->{can_exit} = (defined $prebuf) ? 0 : 1;
    while (1) {
        my $rlen;
        if ( $rlen = length $prebuf ) {
            $buf = $prebuf;
            undef $prebuf;
        }
        else {
            $rlen = $self->read_timeout(
                $conn, \$buf, MAX_REQUEST_SIZE - length($buf), length($buf),
                $is_keepalive ? $self->{keepalive_timeout} : $self->{timeout},
            ) or return;
        }
        $self->{can_exit} = 0;
        my $reqlen = parse_http_request($buf, $env);
        if ($reqlen >= 0) {
            # handle request
            my $protocol = $env->{SERVER_PROTOCOL};
            if ($use_keepalive) {
                if ( $protocol eq 'HTTP/1.1' ) {
                    if (my $c = $env->{HTTP_CONNECTION}) {
                        $use_keepalive = undef
                            if $c =~ /^\s*close\s*/i;
                    }
                }
                else {
                    if (my $c = $env->{HTTP_CONNECTION}) {
                        $use_keepalive = undef
                            unless $c =~ /^\s*keep-alive\s*/i;
                    } else {
                        $use_keepalive = undef;
                    }
                }
            }
            $buf = substr $buf, $reqlen;
            my $chunked = do { no warnings; lc delete $env->{HTTP_TRANSFER_ENCODING} eq 'chunked' };
            if (my $cl = $env->{CONTENT_LENGTH}) {
                my $buffer = Plack::TempBuffer->new($cl);
                while ($cl > 0) {
                    my $chunk;
                    if (length $buf) {
                        $chunk = $buf;
                        $buf = '';
                    } else {
                        $self->read_timeout(
                            $conn, \$chunk, $cl, 0, $self->{timeout})
                            or return;
                    }
                    $buffer->print($chunk);
                    $cl -= length $chunk;
                }
                $env->{'psgi.input'} = $buffer->rewind;
            }
            elsif ($chunked) {
                my $buffer = Plack::TempBuffer->new;
                my $chunk_buffer = '';
                my $length;
                DECHUNK: while(1) {
                    my $chunk;
                    if ( length $buf ) {
                        $chunk = $buf;
                        $buf = '';
                    }
                    else {
                        $self->read_timeout($conn, \$chunk, CHUNKSIZE, 0, $self->{timeout})
                            or return;
                    }

                    $chunk_buffer .= $chunk;
                    while ( $chunk_buffer =~ s/^(([0-9a-fA-F]+).*\015\012)// ) {
                        my $trailer   = $1;
                        my $chunk_len = hex $2;
                        if ($chunk_len == 0) {
                            last DECHUNK;
                        } elsif (length $chunk_buffer < $chunk_len + 2) {
                            $chunk_buffer = $trailer . $chunk_buffer;
                            last;
                        }
                        $buffer->print(substr $chunk_buffer, 0, $chunk_len, '');
                        $chunk_buffer =~ s/^\015\012//;
                        $length += $chunk_len;
                    }
                }
                $env->{CONTENT_LENGTH} = $length;
                $env->{'psgi.input'} = $buffer->rewind;
            } else {
                if ( $buf =~ m!^(?:GET|HEAD)! ) { #pipeline
                    $pipelined_buf = $buf;
                    $use_keepalive = 1; #force keepalive
                } # else clear buffer
                $env->{'psgi.input'} = $null_io;
            }

            if ( $env->{HTTP_EXPECT} ) {
                if ( $env->{HTTP_EXPECT} eq '100-continue' ) {
                    $self->write_all($conn, "HTTP/1.1 100 Continue\015\012\015\012")
                        or return;
                } else {
                    $res = [417,[ 'Content-Type' => 'text/plain', 'Connection' => 'close' ], [ 'Expectation Failed' ] ];
                    last;
                }
            }

            $res = Plack::Util::run_app $app, $env;
            last;
        }
        if ($reqlen == -2) {
            # request is incomplete, do nothing
        } elsif ($reqlen == -1) {
            # error, close conn
            last;
        }
    }

    if (ref $res eq 'ARRAY') {
        $self->_handle_response($env->{SERVER_PROTOCOL}, $res, $conn, \$use_keepalive);
    } elsif (ref $res eq 'CODE') {
        $res->(sub {
            $self->_handle_response($env->{SERVER_PROTOCOL}, $_[0], $conn, \$use_keepalive);
        });
    } else {
        die "Bad response $res";
    }
    if ($self->{term_received}) {
        exit 0;
    }

    return ($use_keepalive, $pipelined_buf);
}

sub _handle_response {
    my($self, $protocol, $res, $conn, $use_keepalive_r) = @_;
    my $status_code = $res->[0];
    my $headers = $res->[1];
    my $body = $res->[2];

    my @lines;
    my %send_headers;
    for (my $i = 0; $i < @$headers; $i += 2) {
        my $k = $headers->[$i];
        my $v = $headers->[$i + 1];
        my $lck = lc $k;
        if ($lck eq 'connection') {
            $$use_keepalive_r = undef
                if $$use_keepalive_r && lc $v ne 'keep-alive';
        } else {
            push @lines, "$k: $v\015\012";
            $send_headers{$lck} = $v;
        }
    }
    if ( ! exists $send_headers{server} ) {
        unshift @lines, "Server: $self->{server_software}\015\012";
    }
    if ( ! exists $send_headers{date} ) {
        unshift @lines, "Date: @{[HTTP::Date::time2str()]}\015\012";
    }

    # try to set content-length when keepalive can be used, or disable it
    my $use_chunked;
    if ( $protocol eq 'HTTP/1.0' ) {
        if ($$use_keepalive_r) {
            if (defined $send_headers{'content-length'}
                || defined $send_headers{'transfer-encoding'}) {
                # ok
            }
            elsif ( ! Plack::Util::status_with_no_entity_body($status_code)
                    && defined(my $cl = Plack::Util::content_length($body))) {
                push @lines, "Content-Length: $cl\015\012";
            }
            else {
                $$use_keepalive_r = undef
            }
        }
        push @lines, "Connection: keep-alive\015\012" if $$use_keepalive_r;
        push @lines, "Connection: close\015\012" if !$$use_keepalive_r; #fmm..
    }
    elsif ( $protocol eq 'HTTP/1.1' ) {
        if (defined $send_headers{'content-length'}
                || defined $send_headers{'transfer-encoding'}) {
            # ok
        } elsif ( !Plack::Util::status_with_no_entity_body($status_code) ) {
            push @lines, "Transfer-Encoding: chunked\015\012";
            $use_chunked = 1;
        }
        push @lines, "Connection: close\015\012" unless $$use_keepalive_r;

    }

    unshift @lines, "HTTP/1.1 $status_code @{[ HTTP::Status::status_message($status_code) ]}\015\012";
    push @lines, "\015\012";

    if (defined $body && ref $body eq 'ARRAY' && @$body == 1
            && length $body->[0] < 8192) {
        # combine response header and small request body
        my $buf = $body->[0];
        if ($use_chunked ) {
            my $len = length $buf;
            $buf = sprintf("%x",$len) . "\015\012" . $buf . "\015\012" . '0' . "\015\012\015\012";
        }
        $self->write_all(
            $conn, join('', @lines, $buf), $self->{timeout},
        );
        return;
    }
    $self->write_all($conn, join('', @lines), $self->{timeout})
        or return;

    if (defined $body) {
        my $failed;
        my $completed;
        my $body_count = (ref $body eq 'ARRAY') ? $#{$body} + 1 : -1;
        Plack::Util::foreach(
            $body,
            sub {
                unless ($failed) {
                    my $buf = $_[0];
                    --$body_count;
                    if ( $use_chunked ) {
                        my $len = length $buf;
                        return unless $len;
                        $buf = sprintf("%x",$len) . "\015\012" . $buf . "\015\012";
                        if ( $body_count == 0 ) {
                            $buf .= '0' . "\015\012\015\012";
                            $completed = 1;
                        }
                    }
                    $self->write_all($conn, $buf, $self->{timeout})
                        or $failed = 1;
                }
            },
        );
        $self->write_all($conn, '0' . "\015\012\015\012", $self->{timeout}) if $use_chunked && !$completed;
    } else {
        return Plack::Util::inline_object
            write => sub {
                my $buf = $_[0];
                if ( $use_chunked ) {
                    my $len = length $buf;
                    return unless $len;
                    $buf = sprintf("%x",$len) . "\015\012" . $buf . "\015\012"
                }
                $self->write_all($conn, $buf, $self->{timeout})
            },
            close => sub {
                $self->write_all($conn, '0' . "\015\012\015\012", $self->{timeout}) if $use_chunked;
            };
    }
}

# returns value returned by $cb, or undef on timeout or network error
sub do_io {
    my ($self, $is_write, $sock, $buf, $len, $off, $timeout) = @_;
    my $ret;
    unless ($is_write || delete $self->{_is_deferred_accept}) {
        goto DO_SELECT;
    }
 DO_READWRITE:
    # try to do the IO
    if ($is_write) {
        $ret = syswrite $sock, $buf, $len, $off
            and return $ret;
    } else {
        $ret = sysread $sock, $$buf, $len, $off
            and return $ret;
    }
    unless ((! defined($ret)
                 && ($! == EINTR || $! == EAGAIN || $! == EWOULDBLOCK))) {
        return;
    }
    # wait for data
 DO_SELECT:
    while (1) {
        my ($rfd, $wfd);
        my $efd = '';
        vec($efd, fileno($sock), 1) = 1;
        if ($is_write) {
            ($rfd, $wfd) = ('', $efd);
        } else {
            ($rfd, $wfd) = ($efd, '');
        }
        my $start_at = time;
        my $nfound = select($rfd, $wfd, $efd, $timeout);
        $timeout -= (time - $start_at);
        last if $nfound;
        return if $timeout <= 0;
    }
    goto DO_READWRITE;
}

# returns (positive) number of bytes read, or undef if the socket is to be closed
sub read_timeout {
    my ($self, $sock, $buf, $len, $off, $timeout) = @_;
    $self->do_io(undef, $sock, $buf, $len, $off, $timeout);
}

# returns (positive) number of bytes written, or undef if the socket is to be closed
sub write_timeout {
    my ($self, $sock, $buf, $len, $off, $timeout) = @_;
    $self->do_io(1, $sock, $buf, $len, $off, $timeout);
}

# writes all data in buf and returns number of bytes written or undef if failed
sub write_all {
    my ($self, $sock, $buf, $timeout) = @_;
    my $off = 0;
    while (my $len = length($buf) - $off) {
        my $ret = $self->write_timeout($sock, $buf, $len, $off, $timeout)
            or return;
        $off += $ret;
    }
    return length $buf;
}

sub DESTROY {
    my ($self) = @_;
    while (my $f = shift @{$self->{_unlink}}) {
        unlink $f;
    }
}

1;