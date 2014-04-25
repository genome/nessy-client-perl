package Nessy::StateMachineFactory::Transition;

use strict;
use warnings;

use Nessy::Properties qw(from to event action_list);

sub new {
    my $class = shift;
    my %params = @_;

    my $self = $class->_verify_params(\%params, qw(from to event action_list));
    return bless $self, $class;
}

sub execute {
    my $self = shift;
    my $from_state = shift;
    my $event = shift;

    my $next_state = $self->to->new();

    my $actions = $self->action_list;
    for (my $i = 0; $i < @$actions; $i++) {
        unless ($actions->[$i]->($from_state, $event, $next_state)) {
            Carp::croak("Action $i returned false during transition ".$self->as_string);
        }
    }

    return $next_state;
}

sub lookup_key {
    my $self = shift;

    $self->from->lookup_key($self->event);
}

sub as_string {
    my $self = shift;

    return sprintf("from %s to %s with event %s",
                $self->from, $self->to, $self->event);
}

1;
