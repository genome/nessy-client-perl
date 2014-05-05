package Nessy::Daemon::EventGenerator;

use strict;
use warnings FATAL => 'all';

use Nessy::Daemon::StateMachine;

use Nessy::Properties qw(
    command_interface
    state_machine
);

sub new {
    my $class = shift;
    my %params = @_;

    return bless $class->_verify_params(\%params, qw(
        state_machine
    ));
}


sub start {
    my ($self, $command_interface) = @_;
    $self->_trigger_event($Nessy::Daemon::StateMachine::e_start,
        $command_interface);
}


sub signal {
    my ($self, $command_interface) = @_;
    $self->_trigger_event($Nessy::Daemon::StateMachine::e_signal,
        $command_interface);
}


sub release {
    my ($self, $command_interface) = @_;
    $self->_trigger_event($Nessy::Daemon::StateMachine::e_release,
        $command_interface);
}


sub http_response_callback {
    my ($self, $command_interface, $body, $headers) = @_;

    my $status_code = $headers->{Status};

    my $event_class = $self->_get_event_class($status_code);
    my $event = $event_class->new(
        command_interface => $command_interface);

    if ($status_code == 201 || $status_code == 202) {
        $event->update_url($headers->{location});
    }

    $self->state_machine->handle_event($event);
}

my %_SPECIFIC_EVENT_CLASSES = (
    201 => $Nessy::Daemon::StateMachine::e_http_201,
    202 => $Nessy::Daemon::StateMachine::e_http_202,
    409 => $Nessy::Daemon::StateMachine::e_http_409,
);
my %_GENERIC_EVENT_CLASSES = (
    2 => $Nessy::Daemon::StateMachine::e_http_2xx,
    4 => $Nessy::Daemon::StateMachine::e_http_4xx,
    5 => $Nessy::Daemon::StateMachine::e_http_5xx,
);
sub _get_event_class {
    my ($self, $status_code) = @_;

    if (exists $_SPECIFIC_EVENT_CLASSES{$status_code}) {
        return $_SPECIFIC_EVENT_CLASSES{$status_code};
    } else {
        my $category = int($status_code / 100);
        return $_GENERIC_EVENT_CLASSES{$category};
    }
}


sub timer_callback {
    my ($self, $command_interface) = @_;
    $self->_trigger_event($Nessy::Daemon::StateMachine::e_timer,
        $command_interface);
}


sub timeout_callback {
    my ($self, $command_interface) = @_;
    $self->_trigger_event($Nessy::Daemon::StateMachine::e_timeout,
        $command_interface);
}

sub _trigger_event {
    my $self = shift;
    my $event_class = shift;
    my $command_interface = shift;

    my $event = $event_class->new(command_interface => $command_interface, @_);
    $self->state_machine->handle_event($event);
}


1;
