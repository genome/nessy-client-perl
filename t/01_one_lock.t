#!/usr/bin/env perl

use strict;
use warnings FATAL => qw(all);

use Test::More tests => 82;

use Nessy::Client;
use AnyEvent;
use IO::Socket::INET;
use JSON;

use lib 't/lib';
use Nessy::Client::TestWebServer;

my ($host, $port) =  Nessy::Client::TestWebServer->get_connection_details;
my $url = "http://$host:$port";
my $ttl = 7;
my $client = Nessy::Client->new( url => $url, default_ttl => $ttl);

my $resource_name = 'foo';
my $user_data = { bar => 'stuff goes here' };

test_get_release();
test_get_undef();
test_renewal();
test_waiting_to_activate();

test_revoked_while_activating();
test_http_timeout_while_activating();
test_revoked_while_active();
test_revoked_while_releasing();
test_server_error_while_registering();
test_server_error_while_activating();
test_server_error_while_renewing();
test_server_error_while_releasing();

sub test_get_release {

    my $server_thread_register = Nessy::Client::TestWebServer->new(
        [ 201, ['Location' => "$url/v1/claims/abc"], [], ],
    );

    my $lock = $client->claim($resource_name, user_data => $user_data);

    my($env_register) = $server_thread_register->join;

    is($env_register->{REQUEST_METHOD}, 'POST',
        'Claim request should use POST method');

    is($env_register->{PATH_INFO}, '/v1/claims/',
        'Claim request should access /v1/claims/');

    my $body_json = $env_register->{__BODY__};
    is_deeply($body_json, {
        resource    => $resource_name,
        user_data   => $user_data,
        ttl         => $ttl,
    }, 'The request body should be well formed');

    ok($lock, "Get claim for $resource_name");
    ok(not($lock->_is_released), 'Lock should be active');



    my $server_thread_release = Nessy::Client::TestWebServer->new(
        [204, [], [], ]);

    ok($lock->release, 'Release lock');

    my($env_release) = $server_thread_release->join;

    is($env_release->{REQUEST_METHOD}, 'PATCH',
        'Claim release should use PATCH method');

    is($env_release->{PATH_INFO}, '/v1/claims/abc',
        'Claim releas should access /v1/claims/abc');

    my $release_json = $env_release->{__BODY__};
    is_deeply($release_json, {
        status      => 'released'
    }, 'The request body should be well formed');

    ok($lock->_is_released, 'Lock should be released');
}

sub test_get_undef {

    my $server_thread_register = Nessy::Client::TestWebServer->new(
        [201, ['Location' => "$url/v1/claims/abc"], [], ]);

    my $lock = $client->claim($resource_name);

    $server_thread_register->join();


    my $server_thread_release = Nessy::Client::TestWebServer->new(
        [204, [], [], ]);

    note('release claim by letting it go out of scope');
    undef($lock);

    my($env_release) = $server_thread_release->join;

    is($env_release->{REQUEST_METHOD}, 'PATCH',
        'Claim release should use PATCH method');

    is($env_release->{PATH_INFO}, '/v1/claims/abc',
        'Claim releas should access /v1/claims/abc');

    my $release_json = $env_release->{__BODY__};
    is_deeply($release_json, {
        status      => 'released'
    }, 'The request body should be well formed');
}

sub test_renewal {
    my $server_thread_register = Nessy::Client::TestWebServer->new(
        [201, ['Location' => "$url/v1/claims/abc"], [], ]);

    my $lock = $client->claim($resource_name, ttl => 1);

    $server_thread_register->join();


    my $server_thread_renewal = Nessy::Client::TestWebServer->new(
        [200, [], [], ]);

    my($env_renewal) = $server_thread_renewal->join;

    is($env_renewal->{REQUEST_METHOD}, 'PATCH', 'Claim renewal uses PATCH method');
    is($env_renewal->{PATH_INFO}, '/v1/claims/abc', 'Claim renewal path');
    is_deeply($env_renewal->{__BODY__},
        { ttl => 1 },
        'Claim renewal body');

    my $server_thread_release = Nessy::Client::TestWebServer->new(
        [204, [], [], ]);

    ok($lock->release, 'Release lock');

    my($env_release) = $server_thread_release->join;
}

sub test_waiting_to_activate {
    my $server_thread_register = Nessy::Client::TestWebServer->new(
        [ 202, [ Location => "$url/v1/claims/abc" ], [] ],
        [ 409, [], [] ],
        [ 409, [], [] ],
        [ 200, [], [] ],
    );

    my $lock = $client->claim($resource_name, ttl => 1);

    my(@envs) = $server_thread_register->join();
    is(scalar(@envs), 4, 'Server got 4 requests');

    my @expected = (
        {   REQUEST_METHOD => 'POST',
            PATH_INFO => '/v1/claims/',
            __BODY__ => { resource => $resource_name, ttl => 1 }
        },
        {   REQUEST_METHOD => 'PATCH',
            PATH_INFO => '/v1/claims/abc',
            __BODY__ => { status => 'active' },
        },
        {   REQUEST_METHOD => 'PATCH',
            PATH_INFO => '/v1/claims/abc',
            __BODY__ => { status => 'active' },
        },
        {   REQUEST_METHOD => 'PATCH',
            PATH_INFO => '/v1/claims/abc',
            __BODY__ => { status => 'active' },
        },
    );

    _envs_are_as_expected(\@envs, \@expected);

    my $server_thread_release = Nessy::Client::TestWebServer->new(
        [204, [], [], ]);
    ok($lock->release, 'Release lock');
    $server_thread_release->join;
}

sub _envs_are_as_expected {
    my($got, $expected) = @_;

    for (my $i = 0; $i < @$expected; $i++) {
        my $expected_env = $expected->[$i];
        my $got_env = $got->[$i];
        foreach my $key ( keys %$expected_env ) {
            is_deeply($got_env->{$key}, $expected_env->{$key}, "request $i env $key matches");
        }
    }
}



sub test_revoked_while_activating {
    my $server_thread_register = Nessy::Client::TestWebServer->new(
        [ 202, [ Location => "$url/v1/claims/abc" ], [] ],
        [ 400, [], [] ],
    );

    my $warning_message = '';
    local $SIG{__WARN__} = sub { $warning_message = shift };
    my $expected_file = __FILE__;
    my $expected_line = __LINE__ + 1;
    my $lock = $client->claim($resource_name, ttl => 1);
    ok(! $lock, 'lock was rejected');
    like($warning_message,
        qr(claim $resource_name at $expected_file:$expected_line failed: 400: activating: bad request),
        'Got expected warning');

    my(@envs) = $server_thread_register->join();
    is(scalar(@envs), 2, 'Server got 2 requests');

    my @expected = (
        {   REQUEST_METHOD => 'POST',
            PATH_INFO => '/v1/claims/',
            __BODY__ => { resource => $resource_name, ttl => 1 }
        },
        {   REQUEST_METHOD => 'PATCH',
            PATH_INFO => '/v1/claims/abc',
            __BODY__ => { status => 'active' },
        },
    );

    _envs_are_as_expected(\@envs, \@expected);
}

sub test_http_timeout_while_activating {
    my $server_thread_register_timeout = Nessy::Client::TestWebServer->new(
        [ 202, [ Location => "$url/v1/claims/abc" ], [] ],
        'BAIL OUT',
    );

    my $condvar = AnyEvent->condvar;
    $client->claim($resource_name, ttl => 1, cb => $condvar);

    my(@envs) = $server_thread_register_timeout->join();

    is(scalar(@envs), 2, 'Server got 2 requests');
    my @expected = (
        {   REQUEST_METHOD => 'POST',
            PATH_INFO => '/v1/claims/',
            __BODY__ => { resource => $resource_name, ttl => 1 }
        },
        {   REQUEST_METHOD => 'PATCH',
            PATH_INFO => '/v1/claims/abc',
            __BODY__ => { status => 'active' },
        },
    );

    _envs_are_as_expected(\@envs, \@expected);

    my $server_thread_register = Nessy::Client::TestWebServer->new(
        [ 200, [], [] ],
        [ 204, [], [] ],
    );
    my $lock = $condvar->recv;
    isa_ok($lock, 'Nessy::Claim');

    ok($lock->release, 'Release lock');

    my @env_register = $server_thread_register->join;

    is(scalar(@env_register), 2, 'Server got 2 requests');

    _envs_are_as_expected(\@env_register, [
        {   REQUEST_METHOD => 'PATCH',
            PATH_INFO => '/v1/claims/abc',
            __BODY__ => { status => 'active' },
        },
        {   REQUEST_METHOD => 'PATCH',
            PATH_INFO => '/v1/claims/abc',
            __BODY__ => { status => 'released' },
        },
    ]);
}

sub test_revoked_while_active {
    _test_revoked_lock(
        [ 201, ['Location' => "$url/v1/claims/abc"], [] ], # register
        [ 200, [], [], ],       # renew
        [ 400, [], [], ],       # fail on second renewal
    );
}

sub test_revoked_while_releasing {
    _test_revoked_lock(
        [ 201, ['Location' => "$url/v1/claims/abc"], [] ], # register
        [ 409, [], [], ],       # fail on releasing
    );
}

sub _test_revoked_lock {
    my @server_responses = @_;
    # Start a new daemon so it will see the env var below and not kill us
    local $ENV{'NESSY_TEST'} = 1;
    my $client = Nessy::Client->new( url => $url, default_ttl => $ttl);

    my $got_sigterm = 0;
    local $SIG{TERM} = sub { $got_sigterm++ };
    local $SIG{ALRM} = sub { ok(0, 'Daemon did not exit in time') };

    my $server_thread = Nessy::Client::TestWebServer->new(
        @server_responses);

    my $lock = $client->claim($resource_name, ttl => 1);

    my @envs = $server_thread->join();

    alarm(5);
    waitpid($client->pid, 0);
    alarm(0);

    is($got_sigterm, 2, 'Got 2 TERM signals while trying to renew');

    my $got_sigpipe = 0;
    local $SIG{PIPE} = sub { $got_sigpipe++ };
    undef $lock;
    is($got_sigpipe, 1, 'Expected SIGPIPE during destruction of defunct lock');
}

sub test_server_error_while_registering {
    my $server_thread_register = Nessy::Client::TestWebServer->new(
        [ 500, [ Location => "$url/v1/claims/" ], [] ],
    );

    my $warning_message = '';
    local $SIG{__WARN__} = sub { $warning_message = shift };
    my $expected_file = __FILE__;
    my $expected_line = __LINE__ + 1;
    my $lock = $client->claim($resource_name, ttl => 1);
    ok(! $lock, 'lock was rejected');
    like($warning_message,
        qr(claim $resource_name at $expected_file:$expected_line failed: 500: server error),
        'Got expected warning');

    $server_thread_register->join;
}

sub test_server_error_while_releasing {
    my $server_thread_register = Nessy::Client::TestWebServer->new(
        [ 201, [ Location => "$url/v1/claims/abc" ], [] ],
        [ 500, [], [] ],
    );

    my $expected_file = __FILE__;
    my $expected_line = __LINE__ + 1;
    my $lock = $client->claim($resource_name, ttl => 1);

    my $warning_message = '';
    local $SIG{__WARN__} = sub { $warning_message = shift };

    ok(! $lock->release, 'Expecting release to fail');
    like($warning_message,
        qr(release $resource_name failed. Claim originated at $expected_file:$expected_line),
        'Got expected warning');

    $server_thread_register->join;
}

sub test_server_error_while_activating {
    my $server_thread_register = Nessy::Client::TestWebServer->new(
        [ 202, [ Location => "$url/v1/claims/abc" ], [] ],
        [ 500, [], [] ],
        [ 200, [], [] ],
    );

    my $lock = $client->claim($resource_name, ttl => 1);

    my(@envs) = $server_thread_register->join();
    is(scalar(@envs), 3, 'Server got 3 requests');

    my @expected = (
        {   REQUEST_METHOD => 'POST',
            PATH_INFO => '/v1/claims/',
            __BODY__ => { resource => $resource_name, ttl => 1 }
        },
        {   REQUEST_METHOD => 'PATCH',
            PATH_INFO => '/v1/claims/abc',
            __BODY__ => { status => 'active' },
        },
        {   REQUEST_METHOD => 'PATCH',
            PATH_INFO => '/v1/claims/abc',
            __BODY__ => { status => 'active' },
        },
    );

    _envs_are_as_expected(\@envs, \@expected);

    my $server_thread_release = Nessy::Client::TestWebServer->new(
        [204, [], [], ]);
    ok($lock->release, 'Release lock');
    $server_thread_release->join;
}

sub test_server_error_while_renewing {
    my $server_thread_register = Nessy::Client::TestWebServer->new(
        [ 201, ['Location' => "$url/v1/claims/abc"], [], ],
    );

    my $lock = $client->claim($resource_name, ttl => 1);

    $server_thread_register->join();

    my $server_thread_renewal = Nessy::Client::TestWebServer->new(
        [ 500, [], [] ],
        [ 200, [], [],]
    );

    my(@env_renewal) = $server_thread_renewal->join;

    my @expected = (
        {   REQUEST_METHOD => 'PATCH',
            PATH_INFO => '/v1/claims/abc',
            __BODY__ => { ttl => 1 },
        },
        {   REQUEST_METHOD => 'PATCH',
            PATH_INFO => '/v1/claims/abc',
            __BODY__ => { ttl => 1 },
        },
    );

    _envs_are_as_expected(\@env_renewal, \@expected);

    my $server_thread_release = Nessy::Client::TestWebServer->new(
        [204, [], [], ]);

    ok($lock->release, 'Release lock');

    my($env_release) = $server_thread_release->join;
}

