use strict;
use warnings;

use Test::More tests => 32;
use Test::Exception;

use Nessy::StateMachineFactory;

basic_state_machine();
conflict_state_machine();
loop_state_machine();

duplicate_state();
duplicate_event();
duplicate_transition();

returning_false_from_action_throws_exception();
modifying_concrete_sm_throws_exception();
changing_start_state_throws_exception();
missing_start_state_throws_exception();

unknown_event_throws_exception_in_transition();

sub duplicate_state {
    _duplicate_thing('define_state');
}

sub duplicate_event {
    _duplicate_thing('define_event');
}
sub _duplicate_thing {
    my $thing = shift;

    my $f = Nessy::StateMachineFactory->new();
    $f->$thing('foo');

    dies_ok { $f->$thing('foo') } "Defining duplicate $thing throws exception";
}


sub basic_state_machine {
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
}

sub conflict_state_machine {
    my $f = Nessy::StateMachineFactory->new();

    my $start_state = $f->define_start_state('start');
    ok($start_state, 'define start state');
    my $middle_state = $f->define_state('middle');
    ok($middle_state, 'define middle state');
    my $forbidden_state = $f->define_state('forbidden');
    ok($forbidden_state, 'define middle state');
    my $end_state = $f->define_state('end');
    ok($end_state, 'define end state');

    my $go_event_type = $f->define_event('go');
    ok($go_event_type, 'Define go event');
    my $forbidden_event_type = $f->define_event('forbidden');
    ok($forbidden_event_type, 'Define forbidden event');

    $f->define_transitions(
        [ $start_state, $go_event_type, $middle_state, [ sub { ok(1, 'Fire transition from start to middle') } ] ],
        [ $start_state, $forbidden_event_type, $forbidden_state, [ sub { ok(0, 'Should not fire to forbidden') } ] ],
        [ $middle_state, $go_event_type, $end_state, [ sub { ok(1, 'Fire transition from middle to end') } ] ],
    );

    my $sm = $f->produce_state_machine();
    ok($sm, 'Make a state machine');

    my $go_event = $go_event_type->new();
    ok($go_event, 'instantiate a go event');

    $sm->handle_event($go_event);
    $sm->handle_event($go_event);
}

sub loop_state_machine {
    my $f = Nessy::StateMachineFactory->new();

    my $start_state = $f->define_start_state('start');
    ok($start_state, 'define start state');
    my $end_state = $f->define_state('end');
    ok($end_state, 'define end state');

    my $loop_event_type = $f->define_event('loop');
    my $break_event_type = $f->define_event('break');

    my $counter = 0;
    $f->define_transitions(
        [ $start_state, $loop_event_type, $start_state, [ sub {++$counter} ] ],
        [ $start_state, $break_event_type, $end_state, [ sub { ok(1, 'loop ended') } ] ],
    );

    my $sm = $f->produce_state_machine();

    my $loop_event = $loop_event_type->new;

    my $loop_times = 3;
    while ($loop_times--) {
        $sm->handle_event($loop_event);
    }

    my $break_event = $break_event_type->new();
    $sm->handle_event($break_event);

    is($counter, 3, 'Looped 3 times');
}

sub returning_false_from_action_throws_exception {
    my $f = Nessy::StateMachineFactory->new();

    my $start_state = $f->define_start_state('start');
    my $loop_event_type = $f->define_event('loop');
    $f->define_transition(
        $start_state, $loop_event_type, $start_state, [ sub { 0 } ]
    );

    my $sm = $f->produce_state_machine();
    my $loop_event = $loop_event_type->new;
    dies_ok { $sm->handle_event($loop_event) } 'Returning false from action throws exception';
}

sub duplicate_transition {
    my $f = Nessy::StateMachineFactory->new();

    my $start_state = $f->define_start_state('start');
    my $loop_event_type = $f->define_event('loop');

    $f->define_transition($start_state, $loop_event_type, $start_state, sub { 1 });
    dies_ok { $f->define_transition($start_state, $loop_event_type, $start_state, sub { 1 })}
        'Adding duplicate transition throws exception';
}

sub modifying_concrete_sm_throws_exception {
    my $f = Nessy::StateMachineFactory->new();
    my $start_state = $f->define_start_state('start');
    my $loop_event_type = $f->define_event('loop');

    $f->produce_state_machine();

    dies_ok { $f->define_transition($start_state, $loop_event_type, $start_state, []) }
        'Cannot add transition to a concrete state machine';

    dies_ok { $f->define_state('foo') }
        'Cannot add a state to a concrete state machine';

    dies_ok { $f->define_event('foo') }
        'Cannot add an event to a concrete state machine';
}

sub changing_start_state_throws_exception {
    my $f = Nessy::StateMachineFactory->new();
    $f->define_start_state('start');
    dies_ok { $f->define_start_state('foo') }
        'Changing the start state of a factory throws exception';
}

sub missing_start_state_throws_exception {
    my $f = Nessy::StateMachineFactory->new();

    my $state = $f->define_state('foo');
    my $event = $f->define_event('go');
    $f->define_transition($state, $event, $state, []);

    dies_ok { $f->produce_state_machine }
        'produce_state_machine() with no start state throws exception';
}

sub unknown_event_throws_exception_in_transition {
    my $f = Nessy::StateMachineFactory->new();
    my $start_state = $f->define_start_state('start');
    my $other_state = $f->define_state('other');

    my $ping_event = $f->define_event('ping');
    my $pong_event = $f->define_event('pong');

    $f->define_transitions(
        [ $start_state, $ping_event, $other_state, [] ],
        [ $other_state, $pong_event, $start_state, [] ],
    );

    my $sm = $f->produce_state_machine();
    dies_ok { $sm->handle_event($pong_event->new) }
        'Illegal event throws exception';
}
