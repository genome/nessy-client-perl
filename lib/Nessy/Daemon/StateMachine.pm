package Nessy::Daemon::StateMachine;

use strict;
use warnings FATAL => 'all';

use Sub::Install;
use StateMachine::Factory;

our $factory = StateMachine::Factory->new();


# ---------------------------- States ----------------------------------------
# Start state
our $s_new = $factory->define_start_state('NEW');

# Final states
our $s_aborted   = $factory->define_state('ABORTED');
our $s_fail      = $factory->define_state('FAIL');
our $s_released  = $factory->define_state('RELEASED');
our $s_withdrawn = $factory->define_state('WITHDRAWN');

# Long-lasting (wait) states
our $s_active  = $factory->define_state('ACTIVE');
our $s_waiting = $factory->define_state('WAITING');

# Acting states
our $s_aborting    = $factory->define_state('ABORTING');
our $s_activating  = $factory->define_state('ACTIVATING');
our $s_registering = $factory->define_state('REGISTERING');
our $s_releasing   = $factory->define_state('RELEASING');
our $s_renewing    = $factory->define_state('RENEWING');
our $s_withdrawing = $factory->define_state('WITHDRAWING');

# "Wait for retry" states
our $s_retrying_abort    = $factory->define_state('RETRYING_ABORT');
our $s_retrying_activate = $factory->define_state('RETRYING_ACTIVATE');
our $s_retrying_register = $factory->define_state('RETRYING_REGISTER');
our $s_retrying_release  = $factory->define_state('RETRYING_RELEASE');
our $s_retrying_renew    = $factory->define_state('RETRYING_RENEW');
our $s_retrying_withdraw = $factory->define_state('RETRYING_WITHDRAW');


# ---------------------------- Events ----------------------------------------
# Externally triggered events
our $e_start    = $factory->define_event('START', 'command_interface');
our $e_shutdown = $factory->define_event('SHUTDOWN', 'command_interface');
our $e_release  = $factory->define_event('RELEASE', 'command_interface');

# Timed events
our $e_timer   = $factory->define_event('TIMER', 'command_interface');
our $e_timeout = $factory->define_event('TIMEOUT', 'command_interface');

# HTTP response events
our $e_http_201 = $factory->define_event('HTTP_201', 'command_interface',
    'update_url');
our $e_http_202 = $factory->define_event('HTTP_202', 'command_interface',
    'update_url');
our $e_http_2xx = $factory->define_event('HTTP_2XX', 'command_interface');

our $e_http_409 = $factory->define_event('HTTP_409', 'command_interface');
our $e_http_4xx = $factory->define_event('HTTP_4XX', 'command_interface');

our $e_http_5xx = $factory->define_event('HTTP_5XX', 'command_interface');


# ---------------------------- Actions ---------------------------------------
my @NOTIFICATIONS = qw(
    abort_error
    abort_shutdown
    aborted
    active
    new_shutdown
    register_error
    register_shutdown
    register_timeout
    release_error
    release_shutdown
    released
    renew_error
    withdraw_error
    withdraw_shutdown
    withdrawn
);

for my $notification (@NOTIFICATIONS) {
    my $ci_method = 'notify_' . $notification;
    my $action_name = 'a_' . $ci_method;
    Sub::Install::install_sub({
        code => sub {
            my ($from, $event, $to) = @_;

            $event->command_interface->$ci_method();

            1;
        },
        into => __PACKAGE__,
        as => $action_name,
    });
}


sub a_abort_claim {
    my ($from, $event, $to) = @_;
    $event->command_interface->abort_claim();
}

sub a_activate_claim {
    my ($from, $event, $to) = @_;
    $event->command_interface->activate_claim();
}

sub a_create_activate_timer {
    my ($from, $event, $to) = @_;
    $event->command_interface->create_activate_timer;
}

sub a_create_renew_timer {
    my ($from, $event, $to) = @_;
    $event->command_interface->create_renew_timer;
}

sub a_create_retry_timer {
    my ($from, $event, $to) = @_;
    $event->command_interface->create_retry_timer;
}

sub a_create_timeout {
    my ($from, $event, $to) = @_;
    $event->command_interface->create_timeout;
}

sub a_delete_timer {
    my ($from, $event, $to) = @_;
    $event->command_interface->delete_timer();
}

sub a_delete_timeout {
    my ($from, $event, $to) = @_;
    $event->command_interface->delete_timeout();
}


sub a_abandon_last_request {
    my ($from, $event, $to) = @_;
    $event->command_interface->abandon_last_request();
}

sub a_register_claim {
    my ($from, $event, $to) = @_;
    $event->command_interface->register_claim();
}

sub a_renew_claim {
    my ($from, $event, $to) = @_;
    $event->command_interface->renew_claim();
}

sub a_release_claim {
    my ($from, $event, $to) = @_;
    $event->command_interface->release_claim();
}

sub a_reset_retry_backoff {
    my ($from, $event, $to) = @_;
    $event->command_interface->reset_retry_backoff();
}

sub a_set_update_url {
    my ($from, $event, $to) = @_;

    if (!defined($event->update_url)) {
        Carp::confess('update_url not provided in a_set_update_url');
    }
    $event->command_interface->update_url($event->update_url);
}

sub a_withdraw_claim {
    my ($from, $event, $to) = @_;
    $event->command_interface->withdraw_claim();
}


# ---------------------------- Transitions -----------------------------------
$factory->define_transitions(

[ $s_new               , $e_start    , $s_registering       ,  [ \&a_create_timeout        , \&a_register_claim           ]                              ]                        ,
[ $s_new               , $e_shutdown , $s_fail              ,  [ \&a_notify_new_shutdown   ]                              ]                              ,

[ $s_aborting          , $e_shutdown , $s_fail              ,  [ \&a_abandon_last_request  , \&a_notify_abort_shutdown    ]                              ]                        ,
[ $s_aborting          , $e_http_409 , $s_fail              ,  [ \&a_notify_abort_error    ]                              ]                              ,
[ $s_aborting          , $e_http_4xx , $s_fail              ,  [ \&a_notify_abort_error    ]                              ]                              ,
[ $s_aborting          , $e_http_5xx , $s_retrying_abort    ,  [ \&a_create_retry_timer    ]                              ]                              ,
[ $s_aborting          , $e_http_2xx , $s_aborted           ,  [ \&a_notify_aborted        ]                              ]                              ,

[ $s_activating        , $e_shutdown , $s_aborting          ,  [ \&a_delete_timeout        , \&a_abandon_last_request     , \&a_reset_retry_backoff      , \&a_abort_claim        ]                   ]  ,
[ $s_activating        , $e_http_2xx , $s_active            ,  [ \&a_delete_timeout        , \&a_reset_retry_backoff      , \&a_create_renew_timer       , \&a_notify_active      ]                   ]  ,
[ $s_activating        , $e_http_4xx , $s_withdrawing       ,  [ \&a_delete_timeout        , \&a_withdraw_claim           ]                              ]                        ,
[ $s_activating        , $e_http_5xx , $s_retrying_activate ,  [ \&a_create_retry_timer    ]                              ]                              ,
[ $s_activating        , $e_http_409 , $s_waiting           ,  [ \&a_create_activate_timer ]                              ]                              ,
[ $s_activating        , $e_timeout  , $s_withdrawing       ,  [ \&a_abandon_last_request  , \&a_reset_retry_backoff      , \&a_withdraw_claim           ]                        ]                   ,

[ $s_active            , $e_shutdown , $s_aborting          ,  [ \&a_delete_timer          , \&a_abort_claim              ]                              ]                        ,
[ $s_active            , $e_release  , $s_releasing         ,  [ \&a_delete_timer          , \&a_release_claim            ]                              ]                        ,
[ $s_active            , $e_timer    , $s_renewing          ,  [ \&a_renew_claim           ]                              ]                              ,

[ $s_registering       , $e_shutdown , $s_fail              ,  [ \&a_delete_timeout        , \&a_abandon_last_request     , \&a_notify_register_shutdown ]                        ]                   ,
[ $s_registering       , $e_timeout  , $s_fail              ,  [ \&a_abandon_last_request  , \&a_notify_register_timeout  ]                              ]                        ,
[ $s_registering       , $e_http_201 , $s_active            ,  [ \&a_delete_timeout        , \&a_reset_retry_backoff      , \&a_set_update_url           , \&a_create_renew_timer , \&a_notify_active ]  ]  ,
[ $s_registering       , $e_http_409 , $s_fail              ,  [ \&a_delete_timeout        , \&a_notify_register_error    ]                              ]                        ,
[ $s_registering       , $e_http_4xx , $s_fail              ,  [ \&a_delete_timeout        , \&a_notify_register_error    ]                              ]                        ,
[ $s_registering       , $e_http_5xx , $s_retrying_register ,  [ \&a_create_retry_timer    ]                              ]                              ,
[ $s_registering       , $e_http_202 , $s_waiting           ,  [ \&a_reset_retry_backoff   , \&a_set_update_url           , \&a_create_activate_timer    ]                        ]                   ,

[ $s_releasing         , $e_shutdown , $s_fail              ,  [ \&a_abandon_last_request  , \&a_notify_release_shutdown  ]                              ]                        ,
[ $s_releasing         , $e_http_4xx , $s_fail              ,  [ \&a_notify_release_error  ]                              ]                              ,
[ $s_releasing         , $e_http_5xx , $s_retrying_release  ,  [ \&a_create_retry_timer    ]                              ]                              ,
[ $s_releasing         , $e_http_2xx , $s_released          ,  [ \&a_notify_released       ]                              ]                              ,

[ $s_renewing          , $e_shutdown , $s_aborting          ,  [ \&a_abandon_last_request  , \&a_reset_retry_backoff      , \&a_abort_claim              ]                        ]                   ,
[ $s_renewing          , $e_http_2xx , $s_active            ,  [ \&a_reset_retry_backoff   , \&a_create_renew_timer       ]                              ]                        ,
[ $s_renewing          , $e_http_409 , $s_fail              ,  [ \&a_notify_renew_error    ]                              ]                              ,
[ $s_renewing          , $e_http_4xx , $s_fail              ,  [ \&a_notify_renew_error    ]                              ]                              ,
[ $s_renewing          , $e_release  , $s_releasing         ,  [ \&a_abandon_last_request  , \&a_reset_retry_backoff      , \&a_release_claim            ]                        ]                   ,
[ $s_renewing          , $e_http_5xx , $s_retrying_renew    ,  [ \&a_create_retry_timer    ]                              ]                              ,

[ $s_retrying_abort    , $e_shutdown , $s_fail              ,  [ \&a_delete_timer          ]                              ]                              ,
[ $s_retrying_abort    , $e_release  , $s_fail              ,  [ \&a_delete_timer          ]                              ]                              ,
[ $s_retrying_abort    , $e_timer    , $s_aborting          ,  [ \&a_abort_claim           ]                              ]                              ,

[ $s_retrying_activate , $e_shutdown , $s_aborting          ,  [ \&a_delete_timer          , \&a_reset_retry_backoff      , \&a_delete_timeout           , \&a_abort_claim        ]                   ]  ,
[ $s_retrying_activate , $e_timer    , $s_activating        ,  [ \&a_activate_claim        ]                              ]                              ,
[ $s_retrying_activate , $e_timeout  , $s_withdrawing       ,  [ \&a_delete_timer          , \&a_withdraw_claim           ]                              ]                        ,

[ $s_retrying_register , $e_shutdown , $s_fail              ,  [ \&a_delete_timer          , \&a_delete_timeout           ]                              ]                        ,
[ $s_retrying_register , $e_timer    , $s_registering       ,  [ \&a_register_claim        ]                              ]                              ,
[ $s_retrying_register , $e_timeout  , $s_fail              ,  [ \&a_delete_timer          , \&a_notify_register_timeout  ]                              ]                        ,

[ $s_retrying_release  , $e_shutdown , $s_fail              ,  [ \&a_delete_timer          ]                              ]                              ,
[ $s_retrying_release  , $e_timer    , $s_releasing         ,  [ \&a_release_claim         ]                              ]                              ,

[ $s_retrying_renew    , $e_shutdown , $s_aborting          ,  [ \&a_delete_timer          , \&a_abort_claim              ]                              ]                        ,
[ $s_retrying_renew    , $e_release  , $s_releasing         ,  [ \&a_delete_timer          , \&a_release_claim            ]                              ]                        ,
[ $s_retrying_renew    , $e_timer    , $s_renewing          ,  [ \&a_renew_claim           ]                              ]                              ,

[ $s_retrying_withdraw , $e_shutdown , $s_fail              ,  [ \&a_delete_timer          ]                              ]                              ,
[ $s_retrying_withdraw , $e_release  , $s_fail              ,  [ \&a_delete_timer          ]                              ]                              ,
[ $s_retrying_withdraw , $e_timer    , $s_withdrawing       ,  [ \&a_withdraw_claim        ]                              ]                              ,

[ $s_waiting           , $e_shutdown , $s_aborting          ,  [ \&a_delete_timer          , \&a_delete_timeout           , \&a_abort_claim              ]                        ]                   ,
[ $s_waiting           , $e_timer    , $s_activating        ,  [ \&a_activate_claim        ]                              ]                              ,
[ $s_waiting           , $e_timeout  , $s_withdrawing       ,  [ \&a_delete_timer          , \&a_withdraw_claim           ]                              ]                        ,

[ $s_withdrawing       , $e_shutdown , $s_fail              ,  [ \&a_abandon_last_request  , \&a_notify_withdraw_shutdown ]                              ]                        ,
[ $s_withdrawing       , $e_http_409 , $s_fail              ,  [ \&a_notify_withdraw_error ]                              ]                              ,
[ $s_withdrawing       , $e_http_4xx , $s_fail              ,  [ \&a_notify_withdraw_error ]                              ]                              ,
[ $s_withdrawing       , $e_http_5xx , $s_retrying_withdraw ,  [ \&a_create_retry_timer    ]                              ]                              ,
[ $s_withdrawing       , $e_http_2xx , $s_withdrawn         ,  [ \&a_notify_withdrawn      ]                              ]                              ,

);


1;
