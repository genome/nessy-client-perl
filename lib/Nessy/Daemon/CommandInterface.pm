package Nessy::Daemon::CommandInterface;

use strict;
use warnings FATAL => 'all';

use Nessy::Properties qw(event_generator resource _current_timer);

use AnyEvent;
use AnyEvent::HTTP;
use JSON;


sub new {
    my $class = shift;
    my %params = @_;

    return bless $class->_verify_params(\%params,
        qw(event_generator resource)), $class;
}


sub abort_claim {
    my $self = shift;

    $self->_patch_status('aborted');
}


sub activate_claim {
    my $self = shift;

    $self->_patch_status('active');
}


sub create_timer {
    my $self = shift;
    my %params = @_;
    my $seconds = $params{seconds};

    $self->_current_timer(AnyEvent->timer(
        after => $seconds,
        cb => sub {
            $self->event_generator->timer_callback()
        },
    ));

    1;
}


sub delete_timer {
    my $self = shift;
    $self->_current_timer(undef);

    1;
}


sub ignore_last_command {
    my $self = shift;
}


sub notify_claim_withdrawn {
    my $self = shift;
}


sub notify_lock_active {
    my $self = shift;
}


sub notify_lock_released {
    my $self = shift;
}


sub register_claim {
    my $self = shift;
}


sub release_claim {
    my $self = shift;

    $self->_patch_status('released');
}


sub renew_claim {
    my $self = shift;
}


sub terminate_client {
    my $self = shift;
}


sub withdraw_claim {
    my $self = shift;

    $self->_patch_status('withdrawn');
}


sub _patch_status {
    my ($self, $status) = @_;

    return 1;
}


my $json_parser;
sub json_parser {
    $json_parser ||= JSON->new();
}


1;
