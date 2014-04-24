use strict;
use warnings;

use Test::More tests => 24;
use Test::Exception;

use Nessy::StateMachineFactory;

basic_state_machine();
conflict_state_machine();
loop_state_machine();

duplicate_state();
duplicate_event();

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
