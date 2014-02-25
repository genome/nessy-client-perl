#!/usr/bin/env perl

use strict;
use warnings FATAL => qw(all);

use Nessy::Client;
use Sys::Hostname qw(hostname);
use Test::More;
use Time::HiRes qw(gettimeofday);
use JSON;

use lib 't/lib';
use Nessy::Client::TestWebProxy;

if ($ENV{NESSY_SERVER_URL}) {
    plan tests => 23;
}
else {
    plan skip_all => 'Needs nessy-server for testing; '
        .' set NESSY_SERVER_URL to something like http://127.0.0.1/';
}

my $ttl = 7;

test_get_release();
test_renewal();
test_waiting_claim();

sub test_get_release {
    my($client, $proxy) = _make_client_and_proxy();

    my $lock =_claim($client, $proxy);

    ok($lock, 'Got claim');
    ok(! $lock->_is_released, 'Lock should be active');

    my $release_condvar = AnyEvent->condvar;
    $lock->release($release_condvar);
    $proxy->do_one_request;
    ok($release_condvar->recv, 'Release should succeed');
    ok($lock->_is_released, 'Lock should be released');
}

sub test_renewal {
    my($client, $proxy) = _make_client_and_proxy();

    my $ttl = 1;
    my $claim = _claim($client, $proxy, ttl => $ttl);
    ok($claim, 'make claim for renewal');

    my($request, $response);
    my ($renewal_req, $renewal_res) = do_before_timeout(
        ($ttl/4)+1, sub { ($request, $response) = $proxy->do_one_request });

    is($request->method, 'PATCH', 'renewal request is a PATCH');
    is_deeply(JSON::decode_json($request->content),
            { ttl => $ttl},
            'request updates ttl');
    ok($response->is_success, 'Response was success');

    _release($claim, $proxy);
}

sub test_waiting_claim {
    my $proxy = Nessy::Client::TestWebProxy->new($ENV{NESSY_SERVER_URL});
    local $ENV{NESSY_CLIENT_PROXY} = $proxy->url;
    my $client1 = Nessy::Client->new( url => $ENV{NESSY_SERVER_URL}, default_ttl => $ttl);
    my $client2 = Nessy::Client->new( url => $ENV{NESSY_SERVER_URL}, default_ttl => $ttl);

    my $claim1 = _claim($client1, $proxy, ttl => 999, user_data => 'original claim');
    my $resource_name = $claim1->resource_name;
    ok($claim1, 'make claim for contention');

    my $claim2_activated = AnyEvent->condvar;
    $client2->claim($resource_name, cb => $claim2_activated, ttl => 1, user_data => 'waiting claim');
    my($register_request, $register_response) = $proxy->do_one_request();
    is($register_request->method, 'POST', 'Registration request was a POST');
    is_deeply(JSON::decode_json($register_request->content),
        { resource => $resource_name, ttl => 1, user_data => 'waiting claim' },
        'Registration request content');
    is($register_response->code, 202, 'Response was 202');
    my $claim2_location = $register_response->header('Location');
    ok($claim2_location, 'Response includes Location header');

    ok(! $claim2_activated->ready, 'Contested claim is not yet ready');


    my($activate_request1, $activate_response1) = $proxy->do_one_request();
    is($activate_request1->method, 'PATCH', 'Activation request was a PATCH');
    is_deeply(JSON::decode_json($activate_request1->content),
        { status => 'active' },
        'Activation content');
    is($activate_request1->uri, $claim2_location, 'Activation request URI');
    is($activate_response1->code, 409, 'Activation response 409');

    _release($claim1, $proxy);

    my($activate_request2, $activate_response2) = $proxy->do_one_request();
    is($activate_request2->method, 'PATCH', 'Activation request 2 was a PATCH');
    is($activate_request2->content,
        JSON::encode_json({ status => 'active' }),
        'Activation content');
    is($activate_request2->uri, $claim2_location, 'Activation request 2 URI');
    is($activate_response2->code, 200, 'Activation response 200');

    my $claim2 = $claim2_activated->recv;
    ok($claim2, 'Second claim is now active');

    _release($claim2, $proxy);
}

sub _claim {
    my($client, $proxy, @claim_args) = @_;

    my $cv = AnyEvent->condvar;
    my ($resource_name, $user_data) = get_resource_and_user_data();
    $client->claim($resource_name, user_data => $user_data, cb => $cv, @claim_args);
    $proxy->do_one_request();
    return $cv->recv;
}

sub _release {
    my($lock, $proxy) = @_;
    my $cv = AnyEvent->condvar;
    $lock->release($cv);
    $proxy->do_one_request;
    return $cv->recv;
}

sub _make_client_and_proxy {
    my $proxy = Nessy::Client::TestWebProxy->new($ENV{NESSY_SERVER_URL});
    local $ENV{NESSY_CLIENT_PROXY} = $proxy->url;
    my $client = Nessy::Client->new( url => $ENV{NESSY_SERVER_URL}, default_ttl => $ttl);
    return ($client, $proxy);
}

sub do_before_timeout {
    my ($timeout_seconds, $stuff_to_do) = @_;

    local $SIG{ALRM} = sub {};
    alarm($timeout_seconds);
    my @rv = $stuff_to_do->();
    alarm(0);

    return @rv;
}

sub get_resource_and_user_data {
    my $tod  = gettimeofday();
    my %data = (
        'hostname'  => hostname(),
        'time'      => $tod,
    );

    my $resource_name = join ' ', @data{qw(hostname time)};

    return ($resource_name, \%data);
}
