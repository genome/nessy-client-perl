use strict;
use warnings;

use Test::More tests => 8;

use Nessy::StateMachineFactory;

my $f = Nessy::StateMachineFactory->new();

my $start_state = $f->define_start_state('start');
ok($start_state, 'define start state');
my $middle_state = $f->define_state('middle');
ok($middle_state, 'define middle state');
my $end_state = $f->define_state('end');
ok($end_state, 'define end state');

my $go_event_type = $f->define_event('go');
ok($go_event_type, 'Define go event');

$f->define_transitions(
    [ $start_state, $go_event_type, $middle_state, [ sub { ok(1, 'Fire transition from start to middle') } ] ],
    [ $middle_state, $go_event_type, $end_state, [ sub { ok(1, 'Fire transition from middle to end') } ] ],
);

my $sm = $f->produce_state_machine();
ok($sm, 'Make a state machine');

my $go_event = $go_event_type->new();
ok($go_event, 'instantiate a go event');

$sm->handle_event($go_event);
$sm->handle_event($go_event);
