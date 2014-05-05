use strict;
use warnings FATAL => 'all';

use Test::More;
use Test::MockObject;

use AnyEvent;

use lib 't/lib';
use Nessy::Client::TestWebServer;


BEGIN {
    use_ok('Nessy::Daemon::CommandInterface');
}


subtest create_timeout_triggers_callback => sub {
    my $eg = _mock_event_generator();
    my $ci = _create_command_interface($eg);

    _run_in_event_loop(0.5, sub {
        $ci->create_timeout();
    });

    $eg->called_ok('timeout_callback', 'timeout callback called');
};


subtest test_delete_timeout => sub {
    my $eg = _mock_event_generator();
    my $ci = _create_command_interface($eg);

    _run_in_event_loop(0.5, sub {
        $ci->create_timeout();
        $ci->delete_timeout();
    });

    ok(!defined($eg->next_call), 'timeout callback not triggered');
};


subtest create_activate_timer_triggers_callback => sub {
    my $eg = _mock_event_generator();
    my $ci = _create_command_interface($eg);

    _run_in_event_loop(0.5, sub {
        $ci->create_activate_timer();
    });

    $eg->called_ok('timer_callback', 'timer callback called');
};


subtest create_renew_timer_triggers_callback => sub {
    my $eg = _mock_event_generator();
    my $ci = _create_command_interface($eg);

    _run_in_event_loop(0.5, sub {
        $ci->create_renew_timer();
    });

    $eg->called_ok('timer_callback', 'timer callback called');
};


subtest create_retry_timer_triggers_callback => sub {
    my $eg = _mock_event_generator();
    my $ci = _create_command_interface($eg);

    _run_in_event_loop(0.5, sub {
        $ci->create_retry_timer();
    });

    $eg->called_ok('timer_callback', 'timer callback called');
};


subtest delete_timer_callback_triggered => sub {
    my $eg = _mock_event_generator();
    my $ci = _create_command_interface($eg);

    _run_in_event_loop(0.5, sub {
        $ci->create_renew_timer();
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

    $eg->called_ok('http_response_callback', 'register callback called');

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
        $ci->abandon_last_request;
    });

    ok(!defined($eg->next_call), 'register callback not called');
};


subtest test_activate_claim => sub {
    my $server = Nessy::Client::TestWebServer->new(
        [200, [], []]
    );

    my $eg = _mock_event_generator();
    my $ci = _create_command_interface($eg);

    $ci->update_url(_update_url('1'));

    _run_in_event_loop(1, sub {
        $ci->activate_claim;
    });

    $eg->called_ok('http_response_callback', 'activate callback called');

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


subtest test_abort_claim => sub {
    my $server = Nessy::Client::TestWebServer->new(
        [204, [], []]
    );

    my $eg = _mock_event_generator();
    my $ci = _create_command_interface($eg);

    $ci->update_url(_update_url('1'));

    _run_in_event_loop(1, sub {
        $ci->abort_claim;
    });

    $eg->called_ok('http_response_callback', 'abort callback called');

    my ($env) = $server->join;

    is($env->{REQUEST_METHOD}, 'PATCH', 'abort uses PATCH');
    is($env->{PATH_INFO}, '/v1/claims/1/', 'abort path matches');
    is($env->{CONTENT_TYPE}, 'application/json',
        'Content-Type header is correct');
    is($env->{HTTP_ACCEPT}, 'application/json',
        'Accept header is correct');
    is_deeply($env->{__BODY__}, { status => 'aborted' },
        'abort body matches');
};


subtest test_release_claim => sub {
    my $server = Nessy::Client::TestWebServer->new(
        [204, [], []]
    );

    my $eg = _mock_event_generator();
    my $ci = _create_command_interface($eg);

    $ci->update_url(_update_url('1'));

    _run_in_event_loop(1, sub {
        $ci->release_claim;
    });

    $eg->called_ok('http_response_callback', 'release callback called');

    my ($env) = $server->join;

    is($env->{REQUEST_METHOD}, 'PATCH', 'release uses PATCH');
    is($env->{PATH_INFO}, '/v1/claims/1/', 'release path matches');
    is($env->{CONTENT_TYPE}, 'application/json',
        'Content-Type header is correct');
    is($env->{HTTP_ACCEPT}, 'application/json',
        'Accept header is correct');
    is_deeply($env->{__BODY__}, { status => 'released' },
        'release body matches');
};


subtest test_withdraw_claim => sub {
    my $server = Nessy::Client::TestWebServer->new(
        [204, [], []]
    );

    my $eg = _mock_event_generator();
    my $ci = _create_command_interface($eg);

    $ci->update_url(_update_url('1'));

    _run_in_event_loop(1, sub {
        $ci->withdraw_claim;
    });

    $eg->called_ok('http_response_callback', 'withdraw callback called');

    my ($env) = $server->join;

    is($env->{REQUEST_METHOD}, 'PATCH', 'withdraw uses PATCH');
    is($env->{PATH_INFO}, '/v1/claims/1/', 'withdraw path matches');
    is($env->{CONTENT_TYPE}, 'application/json',
        'Content-Type header is correct');
    is($env->{HTTP_ACCEPT}, 'application/json',
        'Accept header is correct');
    is_deeply($env->{__BODY__}, { status => 'withdrawn' },
        'withdraw body matches');
};


subtest test_renew_claim => sub {
    my $server = Nessy::Client::TestWebServer->new(
        [204, [], []]
    );

    my $eg = _mock_event_generator();
    my $ci = _create_command_interface($eg);

    $ci->update_url(_update_url('1'));

    _run_in_event_loop(1, sub {
        $ci->renew_claim;
    });

    $eg->called_ok('http_response_callback', 'renew callback called');

    my ($env) = $server->join;

    is($env->{REQUEST_METHOD}, 'PATCH', 'renew uses PATCH');
    is($env->{PATH_INFO}, '/v1/claims/1/', 'renew path matches');
    is($env->{CONTENT_TYPE}, 'application/json',
        'Content-Type header is correct');
    is($env->{HTTP_ACCEPT}, 'application/json',
        'Accept header is correct');
    is_deeply($env->{__BODY__}, { ttl => 60 },
        'renew body matches');
};


subtest test_notify_renew_error => sub {
    plan tests => 1;
    my $ci = _create_command_interface(undef,
        on_renew_error => sub {
            ok(1, 'on_renew_error callback called'); });

    $ci->notify_renew_error();
};


subtest test_notify_active => sub {
    plan tests => 1;
    my $ci = _create_command_interface(undef,
        on_active => sub { ok(1, 'on_active callback called'); });

    $ci->notify_active();
};


subtest test_notify_withdrawn => sub {
    plan tests => 1;
    my $ci = _create_command_interface(undef,
        on_withdrawn => sub { ok(1, 'on_withdrawn callback called'); });

    $ci->notify_withdrawn();
};


subtest test_notify_released => sub {
    plan tests => 1;
    my $ci = _create_command_interface(undef,
        on_released => sub { ok(1, 'on_released callback called'); });

    $ci->notify_released();
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
        'http_response_callback',
        'timer_callback',
        'timeout_callback',
    );

    return $eg;
}

sub _create_command_interface {
    my $eg = shift;

    Nessy::Daemon::CommandInterface->new(event_generator => $eg,
        resource => _get_resource(),
        submit_url => _submit_url(),
        ttl => 60,
        user_data => {
            sample => 'data',
        },

        activate_seconds => 0.1,
        renew_seconds => 0.1,
        retry_seconds => 0.1,

        timeout_seconds => 0.1,

        # Default callbacks should never be called
        _default_callbacks(),

        max_activate_backoff_factor => 5,
        max_retry_backoff_factor => 5,

        @_,
    );
}

sub _default_callbacks {
    my @CB_NAMES = qw(
        on_abort_error
        on_abort_signal
        on_aborted
        on_activate_error
        on_active
        on_register_error
        on_register_signal
        on_register_timeout
        on_release_error
        on_release_signal
        on_released
        on_renew_error
        on_withdraw_error
        on_withdraw_signal
        on_withdrawn
    );

    my %callbacks;
    for my $name (@CB_NAMES) {
        $callbacks{$name} = sub {
            ok(0, "$name shouldn't be called");
        };
    }
    return %callbacks;
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
