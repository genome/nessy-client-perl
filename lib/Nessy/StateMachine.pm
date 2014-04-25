package Nessy::StateMachine;

use strict;
use warnings;

use Nessy::Properties qw(state _transitions);

use Carp;

sub new {
    my $class = shift;
    my $initial_state = shift;
    my $transitions = shift;

    my $self = bless {}, $class;
    
    $self->_transitions($transitions);

    $self->state( $initial_state );

    return $self;
}

sub handle_event {
    my($self, $event) = @_;

    my $trans = $self->_find_matching_transition($event);
    my $next_state = $trans->execute($self->state, $event);
    $self->state($next_state);
}


sub _find_matching_transition {
    my($self, $event) = @_;

    my $current_state = ref($self->state);
    my $event_type = ref($event);

    my $lookup_key = $current_state->lookup_key( $event_type );
    my $transitions = $self->_transitions;
    my $trans = $transitions->{$lookup_key};
    $trans || Carp::croak("No matching transition from $current_state with event $event_type");

    return $trans;
}

1;
