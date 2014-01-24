package Plack::Handler::Starlight;

use strict;
use warnings;

our $VERSION = '0.0100';

use base qw(Starlight::Server);

use POSIX qw(:sys_wait_h);
use Plack::Util;

use constant CYGWIN_KILL_PROCESS => $^O eq 'cygwin' && eval { require Win32::Process; 1; };

use constant DEBUG => $ENV{PERL_STARLIGHT_DEBUG};

sub new {
    my ($klass, %args) = @_;

    # setup before instantiation
    my $listen_sock;
    my $max_workers = 10;
    for (qw(max_workers workers)) {
        $max_workers = delete $args{$_}
            if defined $args{$_};
    }

    # instantiate and set the variables
    my $self = $klass->SUPER::new(%args);
    if ($^O eq 'MSWin32') {
        # forks are emulated
        $self->{is_multithread}  = Plack::Util::TRUE;
        $self->{is_multiprocess} = Plack::Util::FALSE;
    }
    else {
        # real forks
        $self->{is_multithread}  = Plack::Util::FALSE;
        $self->{is_multiprocess} = Plack::Util::TRUE;
    };
    $self->{listen_sock} = $listen_sock
        if $listen_sock;
    $self->{max_workers} = $max_workers;

    $self->{main_process} = $$;
    $self->{processes} = +{};

    $self;
}

sub run {
    my($self, $app) = @_;

    warn "*** starting main process $$" if DEBUG;
    $self->setup_listener();

    local $SIG{PIPE} = 'IGNORE';

    local $SIG{CHLD} = sub {
        my ($sig) = @_;
        warn "*** SIG$sig received in process $$" if DEBUG;
        local ($!, $?);
        my $pid = waitpid(-1, WNOHANG);
        return if $pid == -1;
        delete $self->{processes}->{$pid};
    };

    my $sigint = $self->{_sigint};
    my $sigterm = $^O eq 'MSWin32' ? 'KILL' : 'TERM';

    if ($self->{max_workers} != 0) {
        local $SIG{$sigint} = local $SIG{TERM} = sub {
            my ($sig) = @_;
            warn "*** SIG$sig received in process $$" if DEBUG;
            $self->{term_received}++;
        };
        while (not $self->{term_received}) {
            warn "*** running ", scalar keys %{$self->{processes}}, " processes" if DEBUG;
            foreach my $pid (keys %{$self->{processes}}) {
                delete $self->{processes}->{$pid} if not kill 0, $pid;
            }
            foreach my $n (1 + scalar keys %{$self->{processes}} .. $self->{max_workers}) {
                $self->_create_process($app);
                $self->_sleep($self->{spawn_interval});
            }
            # slow down main process
            $self->_sleep($self->{main_process_delay});
        }
        if (my @pids = keys %{$self->{processes}}) {
            warn "*** stopping ", scalar @pids, " processes" if DEBUG;
            foreach my $pid (@pids) {
                warn "*** stopping process $pid" if DEBUG;
                kill $sigterm, $pid;
            }
            if (CYGWIN_KILL_PROCESS) {
                $self->_sleep(1);
                foreach my $pid (keys %{$self->{processes}}) {
                    my $winpid = Cygwin::pid_to_winpid($pid) or next;
                    warn "*** terminating process $pid winpid $winpid" if DEBUG;
                    Win32::Process::KillProcess($winpid, 0);
                }
            }
            $self->_sleep(1);
            foreach my $pid (keys %{$self->{processes}}) {
                warn "*** waiting for process ", $pid if DEBUG;
                waitpid $pid, 0;
            }
        }
        warn "*** stopping main process $$" if DEBUG;
        exit 0;
    } else {
        # run directly, mainly for debugging
        local $SIG{$sigint} = local $SIG{TERM} = sub {
            my ($sig) = @_;
            warn "*** SIG$sig received in process $$" if DEBUG;
            exit 0;
        };
        while (1) {
            $self->accept_loop($app, $self->_calc_reqs_per_child());
            $self->_sleep($self->{spawn_interval});
        }
    }
}

sub _sleep {
    my ($self, $t) = @_;
    select undef, undef, undef, $t if $t;
}

sub _create_process {
    my ($self, $app) = @_;
    my $pid = fork;
    return warn "cannot fork: $!" unless defined $pid;

    if ($pid == 0) {
        warn "*** process $$ starting" if DEBUG;
        eval {
            $self->accept_loop($app, $self->_calc_reqs_per_child());
        };
        warn $@ if $@;
        warn "*** process $$ ending" if DEBUG;
        exit 0;
    } else {
        $self->{processes}->{$pid} = 1;
    }
}

sub _calc_reqs_per_child {
    my $self = shift;
    my $max = $self->{max_reqs_per_child};
    if (my $min = $self->{min_reqs_per_child}) {
        srand((rand() * 2 ** 30) ^ $$ ^ time);
        return $max - int(($max - $min + 1) * rand);
    } else {
        return $max;
    }
}

1;
