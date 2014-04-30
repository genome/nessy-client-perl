#!/usr/bin/env perl

use strict;
use warnings FATAL => qw(all);

use Test::More;

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

subtest test_get_release => sub {

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
};

subtest test_get_undef => sub {

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
};

subtest test_renewal => sub {
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
};

subtest test_validate => sub {
    my $server_thread_register = Nessy::Client::TestWebServer->new(
        [201, ['Location' => "$url/v1/claims/abc"], [], ]);

    my $lock = $client->claim($resource_name, ttl => 10);
    $server_thread_register->join();


    my $server_thread_validate = Nessy::Client::TestWebServer->new(
        [200, [], [], ]);
    $SIG{ALRM} = sub { ok(0, 'validate took too long'); exit };
    alarm(3);
    ok($lock->validate(), 'claim validates');
    my($env_renewal) = $server_thread_validate->join;
    alarm(0);

    is($env_renewal->{REQUEST_METHOD}, 'PATCH', 'Claim validate uses PATCH method');
    is($env_renewal->{PATH_INFO}, '/v1/claims/abc', 'Claim validate path');
    is_deeply($env_renewal->{__BODY__},
        { ttl => 10 },
        'Claim validate body');


    my $server_thread_release = Nessy::Client::TestWebServer->new(
        [204, [], [], ]);

    ok($lock->release, 'Release lock');

    my($env_release) = $server_thread_release->join;
};

subtest test_register_timeout => sub {
    my $server_thread_register = Nessy::Client::TestWebServer->new(
        [ 202, [ Location => "$url/v1/claims/abc" ], [] ],
        [ 204, [], [] ],
    );

    my $lock = $client->claim($resource_name, ttl => 2, timeout => 1);
    ok(! $lock, 'attempting claim timed out');

    $server_thread_register->join();
};

subtest test_waiting_to_activate => sub {
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
            __BODY__ => {
                resource => $resource_name,
                ttl => 1,
                user_data => undef,
            }
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
};

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



#subtest test_revoked_while_activating => sub {
#    my $server_thread_register = Nessy::Client::TestWebServer->new(
#        [ 202, [ Location => "$url/v1/claims/abc" ], [] ],
#        [ 400, [], [] ],
#    );
#
#    my $got_sigterm = 0;
#    local $ENV{'NESSY_TEST'} = 1;
#    local $SIG{TERM} = sub { $got_sigterm++ };
#
##    my $warning_message = '';
##    local $SIG{__WARN__} = sub { $warning_message = shift };
#    my $lock = $client->claim($resource_name, ttl => 1);
#    is($got_sigterm, 2, 'got two SIGTERMs');
##    ok(! $lock, 'lock was rejected');
##    like($warning_message,
##        qr/Unexpected response in state 'activating' on resource 'foo' \(HTTP 400\): \(no response body\)/,
##        'Got expected warning');
#
#    my(@envs) = $server_thread_register->join();
#    is(scalar(@envs), 2, 'Server got 2 requests');
#
#    my @expected = (
#        {   REQUEST_METHOD => 'POST',
#            PATH_INFO => '/v1/claims/',
#            __BODY__ => { resource => $resource_name, ttl => 1 }
#        },
#        {   REQUEST_METHOD => 'PATCH',
#            PATH_INFO => '/v1/claims/abc',
#            __BODY__ => { status => 'active' },
#        },
#    );
#
#    _envs_are_as_expected(\@envs, \@expected);
#};

subtest test_http_timeout_while_activating => sub {
    my $server_thread_register_timeout = Nessy::Client::TestWebServer->new(
        [ 202, [ Location => "$url/v1/claims/abc" ], [] ],
        'BAIL OUT',
        [ 200, [ ], [] ],
    );

    my $condvar = AnyEvent->condvar;
    $client->claim($resource_name, ttl => 1, cb => $condvar);

    my(@envs) = $server_thread_register_timeout->join();

    is(scalar(@envs), 2, 'Server got 2 requests');
    my @expected = (
        {   REQUEST_METHOD => 'POST',
            PATH_INFO => '/v1/claims/',
            __BODY__ => {
                resource => $resource_name,
                ttl => 1,
                user_data => undef,
            }
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
};

subtest test_revoked_while_active => sub {
    _test_revoked_lock(
        [ 201, ['Location' => "$url/v1/claims/abc"], [] ], # register
        [ 200, [], [], ],       # renew
        [ 400, [], [], ],       # fail on second renewal
    );
};

subtest test_revoked_while_releasing => sub {
    _test_revoked_lock(
        [ 201, ['Location' => "$url/v1/claims/abc"], [] ], # register
        [ 409, [], [], ],       # fail on releasing
    );
};

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

#subtest test_server_error_while_registering => sub {
#    my $server_thread_register = Nessy::Client::TestWebServer->new(
#        [ 500, [ Location => "$url/v1/claims/" ], [] ],
#    );
#
#    my $warning_message = '';
#    local $SIG{__WARN__} = sub { $warning_message = shift };
#    my $expected_file = __FILE__;
#    my $expected_line = __LINE__ + 1;
#    my $lock = $client->claim($resource_name, ttl => 1);
#    ok(! $lock, 'lock was rejected');
#    like($warning_message,
#        qr/Unexpected response in state 'registering' on resource 'foo' \(HTTP 500\): \(no response body\)/,
#        'Got expected warning');
#
#    $server_thread_register->join;
#};

#subtest test_server_error_while_releasing => sub {
#    my $server_thread_register = Nessy::Client::TestWebServer->new(
#        [ 201, [ Location => "$url/v1/claims/abc" ], [] ],
#        [ 500, [], [] ],
#    );
#
#    my $expected_file = __FILE__;
#    my $expected_line = __LINE__ + 1;
#    my $lock = $client->claim($resource_name, ttl => 1);
#
#    my $warning_message = '';
#    local $SIG{__WARN__} = sub { $warning_message = shift };
#
#    ok(! $lock->release, 'Expecting release to fail');
#    like($warning_message,
#        qr(release $resource_name failed. Claim originated at $expected_file:$expected_line),
#        'Got expected warning');
#
#    $server_thread_register->join;
#};

subtest test_server_error_while_activating => sub {
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
            __BODY__ => {
                resource => $resource_name,
                ttl => 1,
                user_data => undef,
            }
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
};

subtest test_server_error_while_renewing => sub {
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
};

subtest test_release_during_renewing => sub {
    my $server_thread_register = Nessy::Client::TestWebServer->new(
        [ 201, ['Location' => "$url/v1/claims/abc"], []],
        'BLOCK NEXT',
        [200, [], []], # renew
        [204, [], []], # release
    );

    my $lock = $client->claim($resource_name, ttl => 1);
    $server_thread_register->wait_for_block_next();
    my $cond = AnyEvent->condvar;
    $lock->release($cond);
    $server_thread_register->proceed_after_block_next();
    ok($cond->recv(), 'release callback fired');
};

done_testing();
