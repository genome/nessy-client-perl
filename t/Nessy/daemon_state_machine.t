use strict;
use warnings FATAL => 'all';

use Test::More;
use Test::MockObject;


BEGIN {
    use_ok('Nessy::Daemon::StateMachine');
}


subtest 'shortest_release_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_201', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_release', command_interface => $ci);
    _execute_event($sm, 'e_http_2xx', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'delete_timeout', 'reset_retry_backoff', 'update_url', 'create_renew_timer', 'notify_active',
        'delete_timer', 'release_claim',
        'notify_released',
    );
};


subtest 'retry_release_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_201', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_release', command_interface => $ci);
    _execute_event($sm, 'e_http_5xx', command_interface => $ci);
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_http_2xx', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'delete_timeout', 'reset_retry_backoff', 'update_url', 'create_renew_timer', 'notify_active',
        'delete_timer', 'release_claim',
        'create_retry_timer',
        'release_claim',
        'notify_released',
    );
};



subtest 'waiting_to_active_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_202', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_http_2xx', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'reset_retry_backoff', 'update_url', 'create_activate_timer',
        'activate_claim',
        'delete_timeout', 'reset_retry_backoff', 'create_renew_timer', 'notify_active',
    );
};


subtest 'keep_waiting_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_202', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_http_409', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'reset_retry_backoff', 'update_url', 'create_activate_timer',
        'activate_claim',
        'create_activate_timer',
    );
};


subtest 'retry_register_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_5xx', command_interface => $ci);
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_http_202', command_interface => $ci,
        update_url => 'a');

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'create_retry_timer',
        'register_claim',
        'reset_retry_backoff', 'update_url', 'create_activate_timer',
    );
};


subtest 'register_fail_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_4xx', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'delete_timeout', 'notify_register_error',
    );
};


subtest 'registering_withdraw_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_timeout', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'abandon_last_request', 'notify_register_timeout',
    );
};


subtest 'retry_registering_withdraw_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_5xx', command_interface => $ci);
    _execute_event($sm, 'e_timeout', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'create_retry_timer',
        'delete_timer', 'notify_register_timeout',
    );
};


subtest 'registering_abort_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_shutdown', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'delete_timeout', 'abandon_last_request', 'notify_register_shutdown',
    );
};


subtest 'retry_registering_abort_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_5xx', command_interface => $ci);
    _execute_event($sm, 'e_shutdown', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'create_retry_timer',
        'delete_timer', 'delete_timeout',
    );
};


subtest 'withdraw_from_waiting_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_202', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timeout', command_interface => $ci);
    _execute_event($sm, 'e_http_2xx', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'reset_retry_backoff', 'update_url', 'create_activate_timer',
        'delete_timer', 'withdraw_claim',
        'notify_withdrawn',
    );
};


subtest 'retry_withdraw_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_202', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timeout', command_interface => $ci);
    _execute_event($sm, 'e_http_5xx', command_interface => $ci);
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_http_2xx', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'reset_retry_backoff', 'update_url', 'create_activate_timer',
        'delete_timer', 'withdraw_claim',
        'create_retry_timer',
        'withdraw_claim',
        'notify_withdrawn',
    );
};


subtest 'withdaw_fail_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_202', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timeout', command_interface => $ci);
    _execute_event($sm, 'e_http_4xx', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'reset_retry_backoff', 'update_url', 'create_activate_timer',
        'delete_timer', 'withdraw_claim',
        'notify_withdraw_error',
    );
};


subtest 'abort_during_withdraw_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_202', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timeout', command_interface => $ci);
    _execute_event($sm, 'e_shutdown', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'reset_retry_backoff', 'update_url', 'create_activate_timer',
        'delete_timer', 'withdraw_claim',
        'abandon_last_request', 'notify_withdraw_shutdown',
    );
};


subtest 'abort_during_withdraw_retry_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_202', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timeout', command_interface => $ci);
    _execute_event($sm, 'e_http_5xx', command_interface => $ci);
    _execute_event($sm, 'e_shutdown', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'reset_retry_backoff', 'update_url', 'create_activate_timer',
        'delete_timer', 'withdraw_claim',
        'create_retry_timer',
        'delete_timer',
    );
};


subtest 'fail_during_activating_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_202', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_http_4xx', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'reset_retry_backoff', 'update_url', 'create_activate_timer',
        'activate_claim',
        'delete_timeout', 'withdraw_claim',
    );
};


subtest 'retrying_activate_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_202', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_http_5xx', command_interface => $ci);
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_http_2xx', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'reset_retry_backoff', 'update_url', 'create_activate_timer',
        'activate_claim',
        'create_retry_timer',
        'activate_claim',
        'delete_timeout', 'reset_retry_backoff', 'create_renew_timer', 'notify_active',
    );
};


subtest 'withdraw_activating_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_202', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_timeout', command_interface => $ci);
    _execute_event($sm, 'e_http_2xx', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'reset_retry_backoff', 'update_url', 'create_activate_timer',
        'activate_claim',
        'abandon_last_request', 'reset_retry_backoff', 'withdraw_claim',
        'notify_withdrawn',
    );
};


subtest 'withdraw_retrying_activate_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_202', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_http_5xx', command_interface => $ci);
    _execute_event($sm, 'e_timeout', command_interface => $ci);
    _execute_event($sm, 'e_http_2xx', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'reset_retry_backoff', 'update_url', 'create_activate_timer',
        'activate_claim',
        'create_retry_timer',
        'delete_timer', 'withdraw_claim',
        'notify_withdrawn',
    );
};


subtest 'release_failure_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_201', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_release', command_interface => $ci);
    _execute_event($sm, 'e_http_4xx', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'delete_timeout', 'reset_retry_backoff', 'update_url', 'create_renew_timer', 'notify_active',
        'delete_timer', 'release_claim',
        'notify_release_error',
    );
};


subtest 'abort_while_releasing_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_201', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_release', command_interface => $ci);
    _execute_event($sm, 'e_shutdown', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'delete_timeout', 'reset_retry_backoff', 'update_url', 'create_renew_timer', 'notify_active',
        'delete_timer', 'release_claim',
        'abandon_last_request', 'notify_release_shutdown',
    );
};


subtest 'abort_while_retrying_release_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_201', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_release', command_interface => $ci);
    _execute_event($sm, 'e_http_5xx', command_interface => $ci);
    _execute_event($sm, 'e_shutdown', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'delete_timeout', 'reset_retry_backoff', 'update_url', 'create_renew_timer', 'notify_active',
        'delete_timer', 'release_claim',
        'create_retry_timer',
        'delete_timer',
    );
};


subtest 'normal_renew_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_201', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_http_2xx', command_interface => $ci);
    _execute_event($sm, 'e_release', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'delete_timeout', 'reset_retry_backoff', 'update_url', 'create_renew_timer', 'notify_active',
        'renew_claim',
        'reset_retry_backoff', 'create_renew_timer',
        'delete_timer', 'release_claim',
    );
};


subtest 'retry_renew_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_201', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_http_5xx', command_interface => $ci);
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_http_2xx', command_interface => $ci);
    _execute_event($sm, 'e_release', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'delete_timeout', 'reset_retry_backoff', 'update_url', 'create_renew_timer', 'notify_active',
        'renew_claim',
        'create_retry_timer',
        'renew_claim',
        'reset_retry_backoff', 'create_renew_timer',
        'delete_timer', 'release_claim',
    );
};


subtest 'renewing_fail_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_201', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_http_4xx', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'delete_timeout', 'reset_retry_backoff', 'update_url', 'create_renew_timer', 'notify_active',
        'renew_claim',
        'notify_renew_error',
    );
};


subtest 'release_from_renewing' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_201', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_release', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'delete_timeout', 'reset_retry_backoff', 'update_url', 'create_renew_timer', 'notify_active',
        'renew_claim',
        'abandon_last_request', 'reset_retry_backoff', 'release_claim',
    );
};


subtest 'release_from_retrying_renew' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_201', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_http_5xx', command_interface => $ci);
    _execute_event($sm, 'e_release', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'delete_timeout', 'reset_retry_backoff', 'update_url', 'create_renew_timer', 'notify_active',
        'renew_claim',
        'create_retry_timer',
        'delete_timer', 'release_claim',
    );
};


subtest 'abort_from_renewing' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_201', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_shutdown', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'delete_timeout', 'reset_retry_backoff', 'update_url', 'create_renew_timer', 'notify_active',
        'renew_claim',
        'abandon_last_request', 'reset_retry_backoff', 'abort_claim',
    );
};


subtest 'abort_from_retrying_renew' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_201', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_http_5xx', command_interface => $ci);
    _execute_event($sm, 'e_shutdown', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'delete_timeout', 'reset_retry_backoff', 'update_url', 'create_renew_timer', 'notify_active',
        'renew_claim',
        'create_retry_timer',
        'delete_timer', 'abort_claim',
    );
};


subtest 'abort_from_active' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_202', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_http_2xx', command_interface => $ci);
    _execute_event($sm, 'e_shutdown', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'reset_retry_backoff', 'update_url', 'create_activate_timer',
        'activate_claim',
        'delete_timeout', 'reset_retry_backoff', 'create_renew_timer', 'notify_active',
        'delete_timer', 'abort_claim',
    );
};


subtest 'abort_from_activating' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_202', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_shutdown', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'reset_retry_backoff', 'update_url', 'create_activate_timer',
        'activate_claim',
        'delete_timeout', 'abandon_last_request', 'reset_retry_backoff', 'abort_claim',
    );
};


subtest 'abort_from_waiting' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_202', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_shutdown', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'reset_retry_backoff', 'update_url', 'create_activate_timer',
        'delete_timer', 'delete_timeout', 'abort_claim',
    );
};


subtest 'abort_from_retrying_activating' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_202', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_http_5xx', command_interface => $ci);
    _execute_event($sm, 'e_shutdown', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'reset_retry_backoff', 'update_url', 'create_activate_timer',
        'activate_claim',
        'create_retry_timer', 'delete_timer', 'reset_retry_backoff',
        'delete_timeout', 'abort_claim',
    );
};


subtest 'successful_abort_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_201', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_shutdown', command_interface => $ci);
    _execute_event($sm, 'e_http_2xx', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'delete_timeout', 'reset_retry_backoff', 'update_url', 'create_renew_timer', 'notify_active',
        'delete_timer', 'abort_claim',
        'notify_aborted',
    );
};


subtest 'failed_abort_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_201', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_shutdown', command_interface => $ci);
    _execute_event($sm, 'e_http_4xx', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'delete_timeout', 'reset_retry_backoff', 'update_url', 'create_renew_timer', 'notify_active',
        'delete_timer', 'abort_claim',
        'notify_abort_error',
    );
};


subtest 'retry_abort_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_201', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_shutdown', command_interface => $ci);
    _execute_event($sm, 'e_http_5xx', command_interface => $ci);
    _execute_event($sm, 'e_timer', command_interface => $ci);
    _execute_event($sm, 'e_http_2xx', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'delete_timeout', 'reset_retry_backoff', 'update_url', 'create_renew_timer', 'notify_active',
        'delete_timer', 'abort_claim',
        'create_retry_timer',
        'abort_claim',
        'notify_aborted',
    );
};


subtest 'abort_during_aborting_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_201', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_shutdown', command_interface => $ci);
    _execute_event($sm, 'e_shutdown', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'delete_timeout', 'reset_retry_backoff', 'update_url', 'create_renew_timer', 'notify_active',
        'delete_timer', 'abort_claim',
        'abandon_last_request', 'notify_abort_shutdown',
    );
};


subtest 'abort_during_retrying_abort_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_start', command_interface => $ci);
    _execute_event($sm, 'e_http_201', command_interface => $ci,
        update_url => 'a');
    _execute_event($sm, 'e_shutdown', command_interface => $ci);
    _execute_event($sm, 'e_http_5xx', command_interface => $ci);
    _execute_event($sm, 'e_shutdown', command_interface => $ci);

    _verify_calls($ci,
        'create_timeout', 'register_claim',
        'delete_timeout', 'reset_retry_backoff', 'update_url', 'create_renew_timer', 'notify_active',
        'delete_timer', 'abort_claim',
        'create_retry_timer',
        'delete_timer',
    );
};


subtest 'new_shutdown_path' => sub {
    my $sm = $Nessy::Daemon::StateMachine::factory->produce_state_machine();
    ok($sm, 'state machine created');

    my $ci = _mock_command_interface();

    _execute_event($sm, 'e_shutdown', command_interface => $ci);

    _verify_calls($ci,
        'notify_new_shutdown'
    );
};


done_testing();


sub _execute_event {
    my $sm = shift;
    my $event_name = shift;

    no strict;
    my $event_class_name = 'Nessy::Daemon::StateMachine::' . $event_name;
    my $event_class = $$event_class_name;
    $sm->handle_event($event_class->new(@_));
    use strict;
}

sub _mock_command_interface {
    my $ci = Test::MockObject->new();
    $ci->set_true(
        'abandon_last_request',
        'abort_claim',
        'activate_claim',
        'create_activate_timer',
        'create_renew_timer',
        'create_retry_timer',
        'create_timeout',
        'delete_timeout',
        'delete_timer',
        'notify_abort_error',
        'notify_abort_shutdown',
        'notify_aborted',
        'notify_activate_error',
        'notify_active',
        'notify_new_shutdown',
        'notify_register_error',
        'notify_register_shutdown',
        'notify_register_timeout',
        'notify_release_error',
        'notify_release_shutdown',
        'notify_released',
        'notify_renew_error',
        'notify_withdraw_error',
        'notify_withdraw_shutdown',
        'notify_withdrawn',
        'register_claim',
        'release_claim',
        'renew_claim',
        'reset_retry_backoff',
        'update_url',
        'withdraw_claim',
    );

    return $ci;
}

sub _verify_calls {
    my $ci = shift;

    for (my $position = 0; $position < scalar(@_); $position++) {
        my $call = $ci->next_call;
        is($call, $_[$position], sprintf('expected call "%s"', $_[$position]));
    }
    my $call = $ci->next_call;
    ok(!defined($call), 'no extra calls found');
}
