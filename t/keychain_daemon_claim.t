#!/usr/bin/env perl

use strict;
use warnings;

use Nessy::Keychain::Daemon::Claim;

use JSON;
use Carp;
use Data::Dumper;
use Test::More tests => 128;

# defaults when creating a new claim object for testing
our $url = 'http://example.org';
our $resource_name = 'foo';
our $ttl = 1;

test_failed_constructor();
test_constructor();
test_start_state_machine();

test_start_state_machine_failure();

test_registration_response_201();
test_registration_response_202();
test_registration_response_failure();

test_send_activating();
test_activating_response_409();
test_activating_response_200();
test_activating_response_400();

test_send_renewal();
test_renewal_response_200();
test_renewal_response_400();

test_send_release();
test_release_response_204();
test_release_response_400();
test_release_response_409();

test_release_failure();

sub _new_claim {
    my $claim = Nessy::Keychain::Daemon::TestClaim->new(
                url => $url,
                resource_name => $resource_name,
                ttl => $ttl,
                on_fatal_error => sub { Carp::croak("unexpected fatal error: $_[1]") },
                api_version => 'v1',
            );
    return $claim;
}

sub test_failed_constructor {

    my $claim;

    $claim = eval { Nessy::Keychain::Daemon::Claim->new() };
    ok($@, 'Calling new() without args throws an exception');

    my %all_params = (
            url => 'http://test.org',
            resource_name => 'foo',
            ttl => 1,
            on_fatal_error => sub {},
            api_version => 'v1',
        );
    foreach my $missing_arg ( keys %all_params ) {
        my %args = %all_params;
        delete $args{$missing_arg};

        $claim = eval { Nessy::Keychain::Daemon::Claim->new( %args ) };
        like($@,
            qr($missing_arg is a required param),
            "missing arg $missing_arg throws an exception");
    }
}

sub test_constructor {
    my $claim;
    $claim = Nessy::Keychain::Daemon::TestClaim->new(
                url => $url,
                resource_name => $resource_name,
                ttl => $ttl,
                on_fatal_error => sub { Carp::croak('unexpected fatal error') },
                api_version => 'v1',
            );
    ok($claim, 'Create Claim');
}

sub _verify_http_params {
    my $got = shift;
    my @expected = @_;

    is(scalar(@$got), scalar(@expected), 'got '.scalar(@expected).' http request params');
    for (my $i = 0; $i < @expected; $i++) {
        my $code = pop @{$got->[$i]};
        is_deeply($got->[$i], $expected[$i], "http request param $i");
        is(ref($code), 'CODE', "callback for param $i");
    }
}

sub test_start_state_machine {

    my $claim = _new_claim();
    ok($claim, 'Create new Claim');
    is($claim->state, 'new', 'Newly created Claim is in state new');

    $claim->expected_state_transitions('registering');

    my $callback_called = 0;
    my $on_success = sub { $callback_called++ };
    my $on_fail = sub { $callback_called++ };
    my $started = $claim->start(
                    on_success => $on_success,
                    on_fail => $on_fail );
    ok($started,'start()');
    is(scalar($claim->remaining_state_transitions), 0, 'expected state transitions for start()');

    my $params = $claim->_http_method_params();
    my $json = JSON->new();
    _verify_http_params($params,
        [ 'POST' => "${url}/v1/claims",
          headers => {'Content-Type' => 'application/json'},
          body => $json->encode({ resource => $resource_name }),
        ]);

    is($callback_called, 0, 'neither success nor fail callbacks were called');
}

sub test_start_state_machine_failure {
    _test_method_requires_arguments(
        'start',
        [ qw(on_success on_fail) ],
        [ 'on_success is required', 'on_fail is required' ],
    );
}

sub test_release_failure {
    _test_method_requires_arguments(
        'release',
        [ qw(on_success on_fail) ],
        [ 'on_success is required', 'on_fail is required' ],
    );
}

sub _test_method_requires_arguments {
    my($method_name, $required_args, $expected_exceptions) = @_;

    my $claim = _new_claim();

    my $callback_called = 0;
    my $callback = sub { $callback_called++ };

    my $worked = eval { $claim->$method_name() };
    ok(! $worked, "$method_name fails with no args");
    ok($@, 'threw an exception');

    for (my $i = 0; $i < @$required_args; $i++) {
        my @args_this_call = @$required_args;
        my($missing_arg) = splice(@args_this_call, $i, 1);
        @args_this_call = map { $_ => $callback } @args_this_call;

        $worked = eval { $claim->$method_name( @args_this_call ) };
        ok(! $worked, "$method_name without $missing_arg fails");
        like($@, qr($expected_exceptions->[$i]), 'expected exception');
    }
}


sub test_registration_response_201 {
    my $claim = _new_claim();
    ok($claim, 'Create new Claim');

    my($success, $fail) = (0,0);
    my @success_args;
    $claim->on_success_cb(sub { @success_args = @_; $success++ });
    $claim->on_fail_cb(sub { $fail++ });

    $claim->state('registering');
    my $claim_location_url = "${url}/claim/123";

    my $response_handler = $claim->_make_response_generator('claim', 'recv_register_response');
    ok( $response_handler->('', { Status => 201, Location => $claim_location_url}),
        'send 201 response to registration');
    is($claim->state(), 'active', 'Claim state is active');
    ok($claim->timer_watcher, 'Claim created a timer');
    is($success, 1, 'success callback fired');
    is_deeply(\@success_args, [$claim], 'success callback got expected args');
    is($fail, 0, 'fail callback not fired');
    is($claim->claim_location_url, $claim_location_url, 'Claim location URL');
}

sub test_registration_response_202 {
    my $claim = _new_claim();

    $claim->state('registering');
    my $claim_location_url = "${url}/claim/123";

    my $callback_fired = 0;
    $claim->on_success_cb(sub { $callback_fired++ });
    $claim->on_fail_cb(sub { $callback_fired++ });

    my $response_handler = $claim->_make_response_generator('claim', 'recv_register_response');
    ok( $response_handler->('', { Status => 202, Location => $claim_location_url}),
        'send 202 response to registrtation');
    is($claim->state(), 'waiting', 'Claim state is waiting');
    ok($claim->timer_watcher, 'Claim created a timer');
    is($callback_fired, 0, 'neither success nor fail callback fired');
    is($claim->claim_location_url, $claim_location_url, 'Claim location URL');
}

sub test_registration_response_failure {
    my %status_error_message = (
        '400'   => 'bad request',
        '500'   => 'server error',
    );

    while (my ($status, $message) = each %status_error_message) {
        _test_registration_response_failure($status,$message);
    }
}

sub _test_registration_response_failure {
    my ($status_code, $error_message) = @_;
    my $claim = _new_claim();

    $claim->state('registering');

    my($success, $fail) = (0,0);
    my @fail_args;
    $claim->on_success_cb(sub { $success++ });
    $claim->on_fail_cb(sub { @fail_args = @_; $fail++ });

    my $response_handler = $claim->_make_response_generator('claim', 'recv_register_response');
    ok( $response_handler->('', { Status => $status_code }),
        "send $status_code response to registrtation");
    is($claim->state(), 'failed', 'Claim state is failed');
    ok(! $claim->timer_watcher, 'Claim did not created a timer');

    is($success, 0, 'success callback not fired');
    is($fail, 1, 'fail callback fired');
    is_deeply(\@fail_args, [$claim, $error_message], 'Error callback got expected args');

    ok(! $claim->claim_location_url, 'Claim has no location URL');
}

sub test_send_activating {
    my $claim = _new_claim();

    my $callback_fired = 0;
    $claim->on_success_cb(sub { $callback_fired++ });
    $claim->on_fail_cb(sub { $callback_fired++ });

    $claim->state('waiting');
    my $claim_location_url = $claim->claim_location_url( "${url}/claims/123" );
    ok($claim->send_activating(), 'send_activating()');

    my $params = $claim->_http_method_params();
    my $json = JSON->new();
    _verify_http_params($params,
        [ 'PATCH' => $claim_location_url,
          headers => {'Content-Type' => 'application/json'},
          body => $json->encode({ status => 'active' }),
        ]);

    is($claim->state, 'activating', 'state is activating');
    is($callback_fired, 0, 'neither success nor fail callback fired');
}

sub test_activating_response_409 {
    my $claim = _new_claim();

    my $callback_fired = 0;

    $claim->state('activating');
    $claim->on_success_cb(sub { $callback_fired++ });
    $claim->on_fail_cb(sub { $callback_fired++ });

    my $fake_timer_watcher = $claim->timer_watcher('abc');
    my $fake_claim_location_url = $claim->claim_location_url("${url}/claim/abc");

    my $response_handler = $claim->_make_response_generator('claim', 'recv_activating_response');
    ok($response_handler->('', { Status => 409 }),
        'send 409 response to activation');

    is($claim->state, 'waiting', 'Claim state is waiting');
    is($claim->timer_watcher, $fake_timer_watcher, 'ttl timer was not changed');
    is($callback_fired, 0, 'neither success nor fail callback fired');
    is($claim->claim_location_url, $fake_claim_location_url, 'Claim has a location URL');
}

sub test_activating_response_200 {
    my $claim = _new_claim();
    $claim->state('activating');
    $claim->ttl(0);

    my($success, $fail) = (0,0);
    my @success_args;
    $claim->on_success_cb(sub { @success_args = @_; $success++ });
    $claim->on_fail_cb(sub { $fail++ });

    my $exit_cond = AnyEvent->condvar;
    {
        my $activating_timer = $claim->_create_timer_event(
            after => 1,
            cb    => sub { $exit_cond->send(0,
                'The activating timer fired when it should not have') });
        $claim->timer_watcher( $activating_timer );

        my $fake_claim_location_url =
            $claim->claim_location_url("${url}/claim/abc");
        my $response_handler = $claim->_make_response_generator(
            'claim', 'recv_activating_response');
        ok($response_handler->('', { Status => 200 }),
            'send 200 response to activation');

        is($claim->state, 'active', 'Claim state is active');
        ok($claim->timer_watcher, 'Claim has a ttl timer');
        isnt($claim->timer_watcher, $activating_timer,
            'ttl timer was changed');

        is($success, 1, 'success callback fired');
        is_deeply(\@success_args, [ $claim ], 'success callback got expected args');
        is($fail, 0, 'fail callback not fired');
        is($claim->claim_location_url, $fake_claim_location_url,
            'Claim has a location URL');
    }

    $claim->on_send_renewal(sub {$exit_cond->send(1,
        'The activating timer was replaced with the renewal timer')});
    my ($ok, $message) = $exit_cond->recv;
    ok($ok, $message);
}

sub test_activating_response_400 {
    my $claim = _new_claim();
    $claim->state('activating');

    my($success, $fail) = (0,0);
    my @fail_args;
    $claim->on_success_cb(sub { $success++ });
    $claim->on_fail_cb(sub { @fail_args = @_; $fail++ });

    my $fake_timer_watcher = $claim->timer_watcher('abc');

    my $response_handler = $claim->_make_response_generator('claim', 'recv_activating_response');
    ok($response_handler->('', { Status => 400 }),
        'send 400 response to activation');

    is($claim->state, 'failed', 'Claim state is failed');
    ok(! $claim->timer_watcher, 'Claim has no ttl timer');
    is($success, 0, 'success callback not fired');
    is($fail, 1, 'fail callback fired');
    is_deeply(\@fail_args, [ $claim, 'activating: bad request' ], 'fail callback got expected args');
}

sub test_send_renewal {
    my $claim = _new_claim();

    my $callback_fired = 0;
    $claim->on_success_cb(sub { $callback_fired++ });
    $claim->on_fail_cb(sub { $callback_fired++ });

    $claim->state('active');
    my $claim_location_url = $claim->claim_location_url( "${url}/claims/${resource_name}" );
    my $fake_timer_watcher = $claim->timer_watcher('abc');
    ok($claim->send_renewal(), 'send_renewal()');

    my $params = $claim->_http_method_params();
    my $json = JSON->new();
    _verify_http_params($params,
        [ 'PATCH' => $claim_location_url,
          headers => {'Content-Type' => 'application/json'},
          body => $json->encode({ ttl => $ttl/4}),
        ]);

    is($claim->state, 'renewing', 'state is renewing');
    is($claim->claim_location_url, $claim_location_url, 'claim location url did not change');
    is($claim->timer_watcher, $fake_timer_watcher, 'ttl timer watcher url did not change');

    is($callback_fired, 0, 'neither success nor fail callback fired');
}

sub test_renewal_response_200 {
    my $claim = _new_claim();

    my $callback_fired = 0;
    $claim->on_success_cb(sub { $callback_fired++ });
    $claim->on_fail_cb(sub { $callback_fired++ });

    $claim->state('renewing');

    my $fake_timer_watcher = $claim->timer_watcher('abc');
    my $fake_claim_location_url = $claim->claim_location_url("${url}/claim/abc");

    my $response_handler = $claim->_make_response_generator('claim', 'recv_renewal_response');
    ok($response_handler->('', { Status => 200 }),
        'send 200 response to renewal');

    is($claim->state, 'active', 'Claim state is active');
    is($claim->timer_watcher, $fake_timer_watcher, 'ttl timer was not changed');
    is($callback_fired, 0, 'neither success nor fail callback fired');
    is($claim->claim_location_url, $fake_claim_location_url, 'Claim has a location URL');
}

sub test_renewal_response_400 {
    my $claim = _new_claim();

    my $callback_fired = 0;
    $claim->on_success_cb(sub { $callback_fired++ });
    $claim->on_fail_cb(sub { $callback_fired++ });

    my $fatal_error = 0;
    my @fatal_error_args;
    $claim->on_fatal_error(sub { @fatal_error_args = @_; $fatal_error++ });

    my $fake_timer_watcher = $claim->timer_watcher('abc');

    my $response_handler = $claim->_make_response_generator('claim', 'recv_renewal_response');
    ok($response_handler->('', { Status => 400 }),
        'send 400 response to renewal');

    is($claim->state, 'failed', 'Claim state is failed');
    ok(! $claim->timer_watcher, 'Claim has no ttl timer');
    is($callback_fired, 0, 'neither success nor fail callback fired');
    is($fatal_error, 1, 'Fatal error callback fired');
    is_deeply(\@fatal_error_args, [ $claim, 'claim foo failed renewal with code 400' ],
            'fatal error callback got expected args');
}

sub test_send_release {
    my $claim = _new_claim();

    $claim->state('active');
    my $claim_location_url = $claim->claim_location_url( "${url}/claims/${resource_name}" );
    my $fake_timer_watcher = $claim->timer_watcher('abc');

    my $callback_fired = 0;
    my $on_success = sub { $callback_fired++ };
    my $on_fail = sub { $callback_fired++ };
    my $release = $claim->release(
                        on_success => $on_success,
                        on_fail => $on_fail,
                    );
    ok($release, 'send_release()');

    my $params = $claim->_http_method_params();
    my $json = JSON->new();
    _verify_http_params($params,
        [ 'PATCH' => $claim_location_url,
          headers => {'Content-Type' => 'application/json'},
          body => $json->encode({ status => 'released' }),
        ]);

    is($claim->state, 'releasing', 'state is releasing');
    is($claim->claim_location_url, $claim_location_url, 'claim location url did not change');
    is($claim->timer_watcher, undef, 'ttl timer watcher was removed');

    is($callback_fired, 0, 'neither success nor fail callback fired');
}

sub test_release_response_204 {
    my $claim = _new_claim();

    my($success, $fail) = (0,0);
    my @success_args;
    $claim->on_success_cb(sub { @success_args = @_; $success++ });
    $claim->on_fail_cb(sub { $fail++ });

    $claim->state('releasing');

    my $fake_claim_location_url = $claim->claim_location_url("${url}/claim/abc");

    my $response_handler = $claim->_make_response_generator('claim', 'recv_release_response');
    ok($response_handler->('', { Status => 204 }),
        'send 200 response to release');

    is($claim->state, 'released', 'Claim state is released');
    is($claim->timer_watcher, undef, 'ttl timer was removed');
    is($success, 1, 'success callback fired');
    is_deeply(\@success_args, [ $claim ], 'success callback got expected args');
    is($fail, 0, 'fail callback not fired');
    is($claim->claim_location_url, $fake_claim_location_url, 'Claim has a location URL');
}

sub test_release_response_400 {
    my $claim = _new_claim();

    my($success, $fail) = (0,0);
    my @fail_args;
    $claim->on_success_cb(sub { $success++ });
    $claim->on_fail_cb(sub { @fail_args = @_; $fail++ });

    $claim->state('releasing');

    my $fake_claim_location_url = $claim->claim_location_url("${url}/claim/abc");

    my $response_handler = $claim->_make_response_generator('claim', 'recv_release_response');
    ok($response_handler->('', { Status => 400 }),
        'send 400 response to release');

    is($claim->state, 'failed', 'Claim state is failed');
    is($claim->timer_watcher, undef, 'ttl timer was removed');
    is($success, 0, 'success callback not fired');
    is($fail, 1, 'fail callback fired');
    is_deeply(\@fail_args, [ $claim, 'release: bad request' ], 'fail callback got expected args');
    is($claim->claim_location_url, $fake_claim_location_url, 'Claim has a location URL');
}

sub test_release_response_409 {
    my $claim = _new_claim();

    my($success, $fail) = (0,0);
    my @fail_args;
    $claim->on_success_cb(sub { $success++ });
    $claim->on_fail_cb(sub { @fail_args = @_; $fail++ });

    $claim->state('releasing');

    my $fake_claim_location_url = $claim->claim_location_url("${url}/claim/abc");

    my $response_handler = $claim->_make_response_generator('claim', 'recv_release_response');
    ok($response_handler->('', { Status => 409 }),
        'send 409 response to release');

    is($claim->state, 'failed', 'Claim state is failed');
    is($claim->timer_watcher, undef, 'ttl timer was removed');
    is($success, 0, 'success callback not fired');
    is($fail, 1, 'fail callback fired');
    is_deeply(\@fail_args, [ $claim, 'release: lost claim' ], 'fail callback got expected args' );
    is($claim->claim_location_url, $fake_claim_location_url, 'Claim has a location URL');
}

package Nessy::Keychain::Daemon::TestClaim;
BEGIN {
    our @ISA = qw( Nessy::Keychain::Daemon::Claim );
}

sub new {
    my $class = shift;
    my %params = @_;
    my $expected = delete $params{expected_state_transitions};

    my $self = $class->SUPER::new(%params);
    $self->expected_state_transitions(@$expected) if $expected;
    return $self;
}

sub expected_state_transitions {
    my $self = shift;
    my @expected = @_;
    $self->{_expected_state_transitions} = \@expected;
}

sub remaining_state_transitions {
    return @{shift->{_expected_state_transitions}};
}

sub state {
    my $self = shift;
    unless (@_) {
        return $self->SUPER::state();
    }
    my $next = shift;
    my $expected_next_states = $self->{_expected_state_transitions};
    if ($expected_next_states) {
        Carp::croak("Tried to switch to state $next and there was no expected next state") unless (@$expected_next_states);
        my $expected_next = shift @$expected_next_states;
        Carp::croak("next state $next does not match expected next state $expected_next") unless ($next eq $expected_next);
    }
    $self->SUPER::state($next);
}

sub _send_http_request {
    my $self = shift;
    my @params = @_;

    $self->{_http_method_params} ||= [];
    push @{$self->{_http_method_params}}, \@params;
}

sub _http_method_params {
    return shift->{_http_method_params};
}

sub on_send_renewal {
    my $self = shift;
    if (@_) {
        ($self->{_send_renewal}) = @_;
    }
    return $self->{_send_renewal};
}

sub send_renewal {
    my $self = shift; 

    if (my $cb = $self->on_send_renewal) {
        $self->$cb(@_);
    }
    else {
        $self->SUPER::send_renewal(@_);
    }
}

sub _log_error {
    #Throw out log message
}

