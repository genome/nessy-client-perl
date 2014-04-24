package Nessy::StateMachineFactory::EventState;

use strict;
use warnings;

use Nessy::Properties qw();

sub _define_eventstate {
    my($class, $event_name, @property_list) = @_;

    my $event_class = join('::', __PACKAGE__, $event_name);
    {   no strict 'refs';
        my $isa = join('::', $event_class, 'ISA');
        my $base_class = $class->_base_class;
        @$isa = ($base_class);
    }
    Nessy::Properties::import($event_class, @property_list);

    return $event_class;
}

package Nessy::StateMachineFactory::EventStateBase;

sub new {
    my $class = shift;
    my %props = @_;

    my $self = bless {}, $class;
    foreach my $prop ( keys %props ) {
        $self->$prop( $props{$prop} );
    }
    return $self;
}

package Nessy::StateMachineFactory::Event;
BEGIN { our @ISA = qw(Nessy::StateMachineFactory::EventState) }
sub _base_class { 'Nessy::StateMachineFactory::EventBase' }
sub define_event {
    my $class = shift;
    $class->_define_eventstate(@_);
}

package Nessy::StateMachineFactory::EventBase;
BEGIN { our @ISA = qw(Nessy::StateMachineFactory::EventStateBase) }

package Nessy::StateMachineFactory::State;
BEGIN { our @ISA = qw(Nessy::StateMachineFactory::EventState) }
sub _base_class { 'Nessy::StateMachineFactory::StateBase' }
sub define_state {
    my $class = shift;
    $class->_define_eventstate(@_);
}

package Nessy::StateMachineFactory::StateBase;
BEGIN { our @ISA = qw(Nessy::StateMachineFactory::EventStateBase) }

sub lookup_key {
    my($self, $event) = @_;

    $self = ref($self) || $self;
    $event = ref($event) || $event;
    return join(':', $self, $event);
}


1;
