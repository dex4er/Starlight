package Plack::Handler::Stardust;

use strict;
use warnings;

our $VERSION = '0.0100';

use base qw(Stardust::Server);

use threads;
use Plack::Util;

use constant DEBUG => $ENV{PERL_STARDUST_DEBUG};

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
    if (threads->can('isthread')) {
        # forks as threads emulation
        $self->{is_multithread}  = Plack::Util::FALSE;
        $self->{is_multiprocess} = Plack::Util::TRUE;
    }
    else {
        # real threads
        $self->{is_multithread}  = Plack::Util::TRUE;
        $self->{is_multiprocess} = Plack::Util::FALSE;
    };
    $self->{listen_sock} = $listen_sock
        if $listen_sock;
    $self->{max_workers} = $max_workers;

    $self->{main_thread} = threads->self;

    $self;
}

sub run {
    my($self, $app) = @_;

    # EV does not work with threads
    $ENV{PERL_ANYEVENT_MODEL} = 'Perl';
    $ENV{PERL_ANYEVENT_IO_MODEL} = 'Perl';

    # Windows 7 and previous have bad SIGINT handling
    my $sigint = 'INT';
    if ($^O eq 'MSWin32') {
        require Win32;
        my @v = Win32::GetOSVersion();
        if ($v[1]*1000 + $v[2] < 6_002) {
            $sigint = 'NONE';
        }
    };

    $self->setup_listener();

    # Threads don't like simple 'IGNORE'
    local $SIG{PIPE} = sub { 'IGNORE' };

    if ($self->{max_workers} != 0) {
        if ($self->{thread_stack_size}) {
            threads->set_stack_size($self->{thread_stack_size});
        }
        local $SIG{$sigint} = local $SIG{TERM} = sub {
            my ($sig) = @_;
            warn "*** SIG$sig received in thread ", threads->tid if DEBUG;
            $self->{term_received}++;
            if (threads->tid) {
                $self->{main_thread}->kill('TERM');
                foreach my $thr (threads->list(threads::running)) {
                    $thr->kill('TERM') if $thr->tid != threads->tid;
                }
            }
        };
        foreach my $n (1 .. $self->{max_workers}) {
            $self->_create_thread($app);
            $self->_sleep($self->{spawn_interval});
        }
        while (not $self->{term_received}) {
            warn "*** running ", scalar threads->list, " threads" if DEBUG;
            foreach my $thr (threads->list(threads::joinable)) {
                warn "*** wait for thread ", $thr->tid if DEBUG;
                eval {
                    $thr->detach;
                };
                warn $@ if $@;
                $self->_create_thread($app);
                $self->_sleep($self->{spawn_interval});
            }
            # slow down main thread
            $self->_sleep($self->{main_thread_delay});
        }
        foreach my $thr (threads->list) {
            $thr->detach;
        }
    } else {
        # run directly, mainly for debugging
        local $SIG{$sigint} = local $SIG{TERM} = sub {
            my ($sig) = @_;
            warn "*** SIG$sig received in thread ", threads->tid if DEBUG;
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

sub _create_thread {
    my ($self, $app) = @_;
    my $thr = threads->create( {context => 'void'},
        sub {
            my ($self, $app) = @_;
            warn "*** thread ", threads->tid, " starting" if DEBUG;
            eval {
                $self->accept_loop($app, $self->_calc_reqs_per_child());
            };
            warn $@ if $@;
            warn "*** thread ", threads->tid, " ending" if DEBUG;
        },
        $self, $app
    );
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
