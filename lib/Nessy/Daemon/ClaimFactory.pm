package Nessy::Daemon::ClaimFactory;

use strict;
use warnings FATAL => 'all';

use Nessy::Daemon::Claim;
use Nessy::Daemon::CommandInterface;
use Nessy::Daemon::EventGenerator;
use Nessy::Daemon::StateMachine;


sub new {
    my $class = shift;

    my $fsm = $Nessy::Daemon::StateMachine::factory->produce_state_machine;
    my $eg = Nessy::Daemon::EventGenerator->new(state_machine => $fsm);

    my $ci = Nessy::Daemon::CommandInterface->new(
        event_generator => $eg,
        @_
    );

    my $claim = Nessy::Daemon::Claim->new(
        command_interface => $ci,
        event_generator => $eg,
    );

    return $claim;
}


1;
