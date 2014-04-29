use strict;
use warnings FATAL => 'all';

use Test::More;
use Test::MockObject;

use AnyEvent;

use lib 't/lib';
use Nessy::Client::TestWebServer;


use_ok('Nessy::Daemon::CommandInterface');


subtest create_timer_callback_triggered => sub {
    my $eg = _mock_event_generator();
    my $ci = _create_command_interface($eg);

    _run_in_event_loop(0.5, sub {
        $ci->create_timer(seconds => 0.1);
    });

    $eg->called_ok('timer_callback', 'timer callback called');
};


subtest delete_timer_callback_triggered => sub {
    my $eg = _mock_event_generator();
    my $ci = _create_command_interface($eg);

    _run_in_event_loop(0.5, sub {
        $ci->create_timer(seconds => 0.1);
        $ci->delete_timer();
    });

    ok(!defined($eg->next_call), 'timer callback not called');
};


subtest test_register_claim => sub {
    my $server = Nessy::Client::TestWebServer->new(
        [201, ['Location' => _update_url(1)], []]
    );

    my $eg = _mock_event_generator();
    my $ci = _create_command_interface($eg);

    _run_in_event_loop(1, sub {
        $ci->register_claim;
    });

    $eg->called_ok('registration_callback', 'register callback called');

    my ($env) = $server->join;

    is($env->{REQUEST_METHOD}, 'POST', 'register uses POST');
    is($env->{PATH_INFO}, '/v1/claims/', 'POST path is correct');
    is($env->{CONTENT_TYPE}, 'application/json',
        'Content-Type header is correct');
    is($env->{HTTP_ACCEPT}, 'application/json',
        'Accept header is correct');
    is_deeply($env->{__BODY__},
        {
            resource => $ci->resource,
            ttl => $ci->ttl,
            user_data => $ci->user_data,
        },
        'body matches');
};


subtest ignore_expected_response_triggers_no_callback => sub {
    my $eg = _mock_event_generator();
    my $ci = _create_command_interface($eg);

    _run_in_event_loop(1, sub {
        $ci->register_claim;
        $ci->ignore_last_command;
    });

    ok(!defined($eg->next_call), 'register callback not called');
};


subtest test_activate_claim_callback => sub {
    my $server = Nessy::Client::TestWebServer->new(
        [200, [], []]
    );

    my $eg = _mock_event_generator();
    my $ci = _create_command_interface($eg);

    $ci->update_url(_update_url('1'));

    _run_in_event_loop(1, sub {
        $ci->activate_claim;
    });

    $eg->called_ok('activate_callback', 'activate callback called');

    my ($env) = $server->join;

    is($env->{REQUEST_METHOD}, 'PATCH', 'activate uses PATCH');
    is($env->{PATH_INFO}, '/v1/claims/1/', 'activate path matches');
    is($env->{CONTENT_TYPE}, 'application/json',
        'Content-Type header is correct');
    is($env->{HTTP_ACCEPT}, 'application/json',
        'Accept header is correct');
    is_deeply($env->{__BODY__}, { status => 'active' },
        'activate body matches');
};


done_testing();


sub _run_in_event_loop {
    my ($duration, $coderef) = @_;

    my $cv = AnyEvent->condvar;
    my $death_timer = AnyEvent->timer(after => $duration, cb => $cv);

    $coderef->();

    $cv->recv;
}

sub _mock_event_generator {
    my $eg = Test::MockObject->new;
    $eg->set_true(
        'timer_callback',
        'registration_callback',
        'activate_callback',
    );

    return $eg;
}

sub _create_command_interface {
    my $eg = shift;
    my $resource = shift || _get_resource();

    Nessy::Daemon::CommandInterface->new(event_generator => $eg,
        resource => $resource,
        submit_url => _submit_url(),
        ttl => 60,
        user_data => {
            sample => 'data',
        },
    );
}


sub _submit_url {
    my ($host, $port) = Nessy::Client::TestWebServer->get_connection_details;
    return "http://$host:$port/v1/claims/"
}

sub _update_url {
    my $id = shift;

    return _submit_url() . $id . '/';
}

sub rndStr{ join'', @_[ map{ rand @_ } 1 .. shift ] }
sub _get_resource {
    return rndStr 20, 'A'..'Z', 'a'..'z', 0..9, '-', '_', '.';
};
