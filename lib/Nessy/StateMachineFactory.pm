package Nessy::StateMachineFactory;

use strict;
use warnings;

use Nessy::StateMachineFactory::EventState;
use Nessy::StateMachineFactory::Transition;
use Nessy::StateMachine;
use Scalar::Util;

use Nessy::Properties qw(_transitions _initial_state_type _is_concrete);

sub new {
    my $class = shift;

    my $self = { _transitions => {}, _initial_state_type => undef};
    return bless $self, $class;
}

sub define_state {
    my $self = shift;
    my $state_name = shift;

    $state_name .= "_" . Scalar::Util::refaddr($self);

    $self->_verify_not_concrete;
    return Nessy::StateMachineFactory::State->define_state($state_name, @_);
}

sub define_event {
    my $self = shift;
    my $event_name = shift;

    $event_name .= "_" . Scalar::Util::refaddr($self);

    $self->_verify_not_concrete;
    return Nessy::StateMachineFactory::Event->define_event($event_name, @_);

}

sub define_transitions {
    my $self = shift;

    foreach my $listref ( @_ ) {
        $self->define_transition(@$listref);
    }
}

sub _verify_not_concrete {
    my $self = shift;

    if ($self->_is_concrete) {
        Carp::croak("Cannot modify a " . ref($self) . " after producing a state machine");
    }
    return 1;
}


sub define_transition {
    my($self, $from, $event, $to, $action_list) = @_;

    $self->_verify_not_concrete;

    my $trans = Nessy::StateMachineFactory::Transition->new(from => $from, event => $event, to => $to, action_list => $action_list);
    my $lookup_key = $trans->lookup_key();

    my $transitions = $self->_transitions();
    if ($transitions->{$lookup_key}) {
        Carp::croak("Tried to create a conflicting transition " . $trans->as_string
                    . "\n    existing transition: " . $transitions->{$lookup_key}->as_string());
    }

    $transitions->{$lookup_key} = $trans;

    return $trans;
}

sub define_start_state {
    my $self = shift;
    if ($self->_initial_state_type) {
        Carp::croak("Initial state is already " . $self->_initial_state_type);
    }

    my $initial_state_type = $self->define_state(@_);
    $self->_initial_state_type( $initial_state_type );
    return $initial_state_type;
}

sub _state_machine_class { 'Nessy::StateMachine' }

sub produce_state_machine {
    my $self = shift;

    $self->_is_concrete(1);

    unless ($self->_initial_state_type) {
        Carp::croak("define_start_state() was not called");
    }

    my $initial_state = $self->_initial_state_type->new(@_);
    my $transitions = $self->_transitions;
    my $sm = $self->_state_machine_class->new($initial_state, $transitions);
    return $sm;
}

1;
