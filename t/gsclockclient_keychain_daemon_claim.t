#!/usr/bin/env perl

use strict;
use warnings;

use GSCLockClient::Keychain::Daemon::Claim;

use JSON;
use Carp;
use Data::Dumper;
use Test::More tests => 58;

# defaults when creating a new claim object for testing
our $url = 'http://example.org';
our $resource_name = 'foo';
our $ttl = 1;

test_failed_constructor();
test_constructor();
test_start_state_machine();

test_registration_response_201();
test_registration_response_202();
test_registration_response_400();

test_send_activating();
test_activating_response_409();
test_activating_response_200();
test_activating_response_400();

test_send_renewal();

sub _new_claim {
    my $keychain = GSCLockClient::Keychain::Daemon::Fake->new();
    my $claim = GSCLockClient::Keychain::Daemon::TestClaim->new(
                url => $url,
                resource_name => $resource_name,
                keychain => $keychain,
                ttl => $ttl,
            );
    return $claim;
}

sub test_failed_constructor {

    my $claim;

    $claim = eval { GSCLockClient::Keychain::Daemon::Claim->new() };
    ok($@, 'Calling new() without args throws an exception');

    my %all_params = (
            url => 'http://test.org',
            resource_name => 'foo',
            keychain => 'bar',
            ttl => 1,
        );
    foreach my $missing_arg ( keys %all_params ) {
        my %args = %all_params;
        delete $args{$missing_arg};

        $claim = eval { GSCLockClient::Keychain::Daemon::Claim->new( %args ) };
        like($@,
            qr($missing_arg is a required param),
            "missing arg $missing_arg throws an exception");
    }
}

sub test_constructor {
    my $claim;
    my $keychain = GSCLockClient::Keychain::Daemon::Fake->new();
    $claim = GSCLockClient::Keychain::Daemon::TestClaim->new(
                url => $url,
                resource_name => $resource_name,
                keychain => $keychain,
                ttl => $ttl,
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
    ok($claim->start(),'start()');
    is(scalar($claim->remaining_state_transitions), 0, 'expected state transitions for start()');

    my $params = $claim->_http_method_params();
    my $json = JSON->new();
    _verify_http_params($params,
        [ 'POST' => "${url}/claims",
          $json->encode({ resource => $resource_name }),
          'Content-Type' => 'application/json',
        ]);

    my $keychain = $claim->keychain;
    ok(! $keychain->claim_succeeded, 'Keychain was not notified about success');
    ok(! $keychain->claim_failed, 'Keychain was not notified about failure');
}

sub test_registration_response_201 {
    my $claim = _new_claim();
    ok($claim, 'Create new Claim');
    my $keychain = $claim->keychain;

    $claim->state('registering');
    my $claim_location_url = "${url}/claim/123";
    ok( $claim->recv_register_response('', { Status => 201, Location => $claim_location_url}),
        'send 201 response to registration');
    is($claim->state(), 'active', 'Claim state is active');
    ok($claim->ttl_timer_watcher, 'Claim created a timer');
    ok($keychain->claim_succeeded, 'Keychain was notified about success');
    ok(! $keychain->claim_failed, 'Keychain was not notified about failure');
    is($claim->claim_location_url, $claim_location_url, 'Claim location URL');
}

sub test_registration_response_202 {
    my $claim = _new_claim();
    my $keychain = $claim->keychain;

    $claim->state('registering');
    my $claim_location_url = "${url}/claim/123";
    ok( $claim->recv_register_response('', { Status => 202, Location => $claim_location_url}),
        'send 202 response to registrtation');
    is($claim->state(), 'waiting', 'Claim state is waiting');
    ok($claim->ttl_timer_watcher, 'Claim created a timer');
    ok(! $keychain->claim_succeeded, 'Keychain was not notified about success');
    ok(! $keychain->claim_failed, 'Keychain was not notified about failure');
    is($claim->claim_location_url, $claim_location_url, 'Claim location URL');
}

sub test_registration_response_400 {
    my $claim = _new_claim();
    my $keychain = $claim->keychain;

    $claim->state('registering');

    ok( $claim->recv_register_response('', { Status => 400 }),
        'send 400 response to registrtation');
    is($claim->state(), 'failed', 'Claim state is waiting');
    ok(! $claim->ttl_timer_watcher, 'Claim did not created a timer');
    ok(! $keychain->claim_succeeded, 'Keychain was not notified about success');
    ok($keychain->claim_failed, 'Keychain was notified about failure');
    ok(! $claim->claim_location_url, 'Claim has no location URL');
}

sub test_send_activating {
    my $claim = _new_claim();

    $claim->state('waiting');
    my $claim_location_url = $claim->claim_location_url( "${url}/claims/${resource_name}" );
    ok($claim->send_activating(), 'send_activating()');

    my $params = $claim->_http_method_params();
    my $json = JSON->new();
    _verify_http_params($params,
        [ 'PATCH' => $claim_location_url,
          $json->encode({ status => 'active' }),
          'Content-Type' => 'application/json',
        ]);

    is($claim->state, 'activating', 'state is activating');
    my $keychain = $claim->keychain;
    ok(! $keychain->claim_succeeded, 'Keychain was not notified about success');
    ok(! $keychain->claim_failed, 'Keychain was not notified about failure');
}

sub test_activating_response_409 {
    my $claim = _new_claim();
    my $keychain = $claim->keychain;
    $claim->state('activating');

    my $fake_ttl_timer_watcher = $claim->ttl_timer_watcher('abc');
    my $fake_claim_location_url = $claim->claim_location_url("${url}/claim/abc");

    ok($claim->recv_activating_response('', { Status => 409 }),
        'send 409 response to activation');

    is($claim->state, 'waiting', 'Claim state is waiting');
    is($claim->ttl_timer_watcher, $fake_ttl_timer_watcher, 'ttl timer was not changed');
    ok(! $keychain->claim_succeeded, 'Keychain was not notified about success');
    ok(! $keychain->claim_failed, 'Keychain was not notified about failure');
    is($claim->claim_location_url, $fake_claim_location_url, 'Claim has a location URL');
}

sub test_activating_response_200 {
    my $claim = _new_claim();
    my $keychain = $claim->keychain;
    $claim->state('activating');

    my $fake_ttl_timer_watcher = $claim->ttl_timer_watcher('abc');
    my $fake_claim_location_url = $claim->claim_location_url("${url}/claim/abc");

    ok($claim->recv_activating_response('', { Status => 200 }),
        'send 200 response to activation');

    is($claim->state, 'active', 'Claim state is active');
    ok($claim->ttl_timer_watcher, 'Claim has a ttl timer');
    isnt($claim->ttl_timer_watcher, $fake_ttl_timer_watcher, 'ttl timer was changed');
    ok($keychain->claim_succeeded, 'Keychain was notified about success');
    ok(! $keychain->claim_failed, 'Keychain was not notified about failure');
    is($claim->claim_location_url, $fake_claim_location_url, 'Claim has a location URL');
}

sub test_activating_response_400 {
    my $claim = _new_claim();
    my $keychain = $claim->keychain;
    $claim->state('activating');

    my $fake_ttl_timer_watcher = $claim->ttl_timer_watcher('abc');

    ok($claim->recv_activating_response('', { Status => 400 }),
        'send 400 response to activation');

    is($claim->state, 'failed', 'Claim state is active');
    ok(! $claim->ttl_timer_watcher, 'Claim has no ttl timer');
    ok(! $keychain->claim_succeeded, 'Keychain was not notified about success');
    ok($keychain->claim_failed, 'Keychain was notified about failure');
}

sub test_send_renewal {
    my $claim = _new_claim();

    $claim->state('active');
    my $claim_location_url = $claim->claim_location_url( "${url}/claims/${resource_name}" );
    my $fake_ttl_timer_watcher = $claim->ttl_timer_watcher('abc');
    ok($claim->send_renewal(), 'send_renewal()');

    my $params = $claim->_http_method_params();
    my $json = JSON->new();
    _verify_http_params($params,
        [ 'PATCH' => $claim_location_url,
          $json->encode({ ttl => $ttl/4}),
          'Content-Type' => 'application/json',
        ]);

    is($claim->state, 'renewing', 'state is renewing');
    is($claim->claim_location_url, $claim_location_url, 'claim location url did not change');
    is($claim->ttl_timer_watcher, $fake_ttl_timer_watcher, 'ttl timer watcher url did not change');

    my $keychain = $claim->keychain;
    ok(! $keychain->claim_succeeded, 'Keychain was not notified about success');
    ok(! $keychain->claim_failed, 'Keychain was not notified about failure');
}



package GSCLockClient::Keychain::Daemon::TestClaim;
BEGIN {
    our @ISA = qw( GSCLockClient::Keychain::Daemon::Claim );
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
Test::More::diag "going from ".$self->SUPER::state()." to $next, expecting $expected_next";
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


package GSCLockClient::Keychain::Daemon::Fake;
sub new {
    my $class = shift;
    return bless {}, $class;
}

sub claim_failed {
    my $self = shift;
    if (@_) {
        $self->{_claim_failed} = shift;
        Test::More::note("Got claim failed: ".Data::Dumper::Dumper$self->{_claim_failed});
    }
    return $self->{_claim_failed};
}

sub claim_succeeded {
    my $self = shift;
    if (@_) {
        $self->{_claim_succeeded} = shift;
    }
    return $self->{_claim_succeeded};
}



