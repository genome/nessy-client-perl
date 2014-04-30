use strict;
use warnings FATAL => 'all';

use Test::More;
use Test::MockObject;

use AnyEvent;

use_ok('Nessy::Daemon::EventGenerator');

subtest test_timeout_callback => sub {
    _test_generic_callback('timeout_callback', 'timeout');
};


subtest test_timer_callback => sub {
    _test_generic_callback('timer_callback', 'timer');
};


subtest test_start => sub {
    _test_generic_callback('start', 'start');
};


subtest test_signal => sub {
    _test_generic_callback('signal', 'signal');
};


subtest test_release => sub {
    _test_generic_callback('release', 'release');
};


subtest test_http_201 => sub {
    my $sm = _create_state_machine();
    my $ci = _create_command_interface();

    my $eg = Nessy::Daemon::EventGenerator->new(
        command_interface => $ci, state_machine => $sm);

    $eg->http_response_callback('', {Status => 201, Location => 'a'});

    my ($call, $args) = $sm->next_call;

    is($call, 'handle_event', 'handle_event called');

    my ($self, $event) = @$args;
    {
        no warnings 'once';
        ok($event->isa($Nessy::Daemon::StateMachine::e_http_201),
            'release event raised');
    }
    is($event->update_url, 'a', 'update_url set');
    is($event->command_interface, $ci, 'command_interface passed along');
};


subtest test_http_202 => sub {
    my $sm = _create_state_machine();
    my $ci = _create_command_interface();

    my $eg = Nessy::Daemon::EventGenerator->new(
        command_interface => $ci, state_machine => $sm);

    $eg->http_response_callback('', {Status => 202, Location => 'a'});

    my ($call, $args) = $sm->next_call;

    is($call, 'handle_event', 'handle_event called');

    my ($self, $event) = @$args;
    {
        no warnings 'once';
        ok($event->isa($Nessy::Daemon::StateMachine::e_http_202),
            'release event raised');
    }
    is($event->update_url, 'a', 'update_url set');
    is($event->command_interface, $ci, 'command_interface passed along');
};


subtest test_http_200 => sub {
    _test_http_callback(200, '2xx');
};


subtest test_http_204 => sub {
    _test_http_callback(204, '2xx');
};


subtest test_http_400 => sub {
    _test_http_callback(400, '4xx');
};


subtest test_http_401 => sub {
    _test_http_callback(401, '4xx');
};


subtest test_http_403 => sub {
    _test_http_callback(403, '4xx');
};


subtest test_http_404 => sub {
    _test_http_callback(404, '4xx');
};


subtest test_http_409 => sub {
    _test_http_callback(409, '409');
};


subtest test_http_500 => sub {
    _test_http_callback(500, '5xx');
};


subtest test_http_502 => sub {
    _test_http_callback(502, '5xx');
};


done_testing();


sub _create_state_machine {
    my $sm = Test::MockObject->new;

    $sm->set_true(
        'handle_event'
    );
}

sub _create_command_interface {
    return Test::MockObject->new;
}


sub _test_generic_callback {
    my $callback_name = shift;
    my $event_name = shift;

    my $sm = _create_state_machine();
    my $ci = _create_command_interface();

    my $eg = Nessy::Daemon::EventGenerator->new(
        command_interface => $ci, state_machine => $sm);

    $eg->$callback_name();

    my ($call, $args) = $sm->next_call;

    is($call, 'handle_event', 'handle_event called');

    my ($self, $event) = @$args;
    {
        no strict;
        my $full_event_name = 'Nessy::Daemon::StateMachine::e_' . $event_name;
        ok($event->isa($$full_event_name),
            "$event_name event raised");
    }
    is($event->command_interface, $ci, 'command_interface passed along');
};


sub _test_http_callback {
    my $status = shift;
    my $event_status = shift;

    my $sm = _create_state_machine();
    my $ci = _create_command_interface();

    my $eg = Nessy::Daemon::EventGenerator->new(
        command_interface => $ci, state_machine => $sm);

    $eg->http_response_callback('', {Status => $status});

    my ($call, $args) = $sm->next_call;

    is($call, 'handle_event', 'handle_event called');

    my ($self, $event) = @$args;
    {
        no strict;
        my $ev_class = 'Nessy::Daemon::StateMachine::e_http_' . $event_status;
        ok($event->isa($$ev_class), "http_$event_status event raised");
    }
    is($event->command_interface, $ci, 'command_interface passed along');
}
