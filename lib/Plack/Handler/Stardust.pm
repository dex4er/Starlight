package Plack::Handler::Stardust;

use strict;
use warnings;

our $VERSION = '0.0100';

use base qw(Stardust::Server);

use POSIX ":sys_wait_h";
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
    $self->{is_multiprocess} = Plack::Util::TRUE;
    $self->{listen_sock} = $listen_sock
        if $listen_sock;
    $self->{max_workers} = $max_workers;

    $self->{main_process} = $$;
    $self->{processes} = +{};

    $self;
}

sub run {
    my($self, $app) = @_;

    $self->setup_listener();

    local $SIG{PIPE} = 'IGNORE';

    local $SIG{CHLD} = sub {
        my ($sig) = @_;
        warn "*** SIG$sig received in process ", $$ if DEBUG;
        local ($!, $?);
        my $pid = waitpid(-1, WNOHANG);
        return if $pid == -1;
        return unless defined $self->{processes}->{$pid};
        delete $self->{processes}->{$pid};
    };

    if ($self->{max_workers} != 0) {
        local $SIG{INT} = local $SIG{TERM} = sub {
            my ($sig) = @_;
            warn "*** SIG$sig received in process ", $$ if DEBUG;
            $self->{term_received}++;
            if ($$ != $self->{main_process}) {
                kill 'TERM', $self->{main_process};
            }
        };
        while (not $self->{term_received}) {
            warn "*** running ", scalar keys %{$self->{processes}}, " processes" if DEBUG;
            foreach my $n (1 + scalar keys %{$self->{processes}} .. $self->{max_workers}) {
                $self->_create_process($app);
                $self->_sleep($self->{spawn_interval});
            }
            # slow down main process
            $self->_sleep($self->{main_process_delay});
        }
        exit 0;
    } else {
        # run directly, mainly for debugging
        local $SIG{INT} = local $SIG{TERM} = sub {
            my ($sig) = @_;
            warn "*** SIG$sig received in process ", $$ if DEBUG;
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
        warn "*** process ", $$, " starting" if DEBUG;
        eval {
            $self->accept_loop($app, $self->_calc_reqs_per_child());
        };
        warn $@ if $@;
        warn "*** process ", $$, " ending" if DEBUG;
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
