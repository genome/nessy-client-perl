#!/usr/bin/env perl

use strict;
use warnings FATAL => qw(all);

use forks;
use Test::More tests => 17;

use Nessy::Client;
use AnyEvent;
use HTTP::Server::PSGI;
use IO::Socket::INET;
use JSON;

sub _does_http_server_psgi_support_harakiri {
    require Plack;
    if ($Plack::VERSION >= 1.0004) {
        return 1;
    } else {
        return;
    }
}

BEGIN {
    if (! _does_http_server_psgi_support_harakiri()) {
        push @INC, 't/lib';
        require Nessy::Client::HTTPServerPSGI;
    }
}


my ($server, $host, $port) =  _new_http_server();
my $url = "http://$host:$port";
my $ttl = 7;
my $client = Nessy::Client->new( url => $url, default_ttl => $ttl);
my $resource_name = 'foo';
my $user_data = { bar => 'stuff goes here' };

test_get_release();
test_get_undef();
test_renewal();

sub make_server_thread {
    my ($server, @responses) = @_;

    my @envs;
    my($server_thread) = threads->create( sub {
        my $env;
        $server->run( sub {
            $env = shift;
            $env->{__BODY__} = _get_request_body( $env->{'psgi.input'} );
            delete $env->{'psgi.input'};
            delete $env->{'psgi.errors'};
            delete $env->{'psgix.io'};

            my $response = shift @responses;
            push @envs, $env;
            $env->{'psgix.harakiri.commit'} = 1 unless(@responses);
            return $response;
        });
        return @envs;
    });

    return ($server_thread);
}

sub test_get_release {

    my $server_thread_register = make_server_thread($server, [
        201, ['Location' => "$url/v1/claims/abc"], [], ]);

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



    my $server_thread_release = make_server_thread($server, [
        204, [], [], ]);

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

    my $server_thread_register = make_server_thread($server, [
        201, ['Location' => "$url/v1/claims/abc"], [], ]);

    my $lock = $client->claim($resource_name);

    $server_thread_register->join();


    my $server_thread_release = make_server_thread($server, [
        204, [], [], ]);

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
    my $server_thread_register = make_server_thread($server, [
        201, ['Location' => "$url/v1/claims/abc"], [], ]);

    my $lock = $client->claim($resource_name, ttl => 1);

    $server_thread_register->join();


    my $server_thread_renewal = make_server_thread($server, [
        200, [], [], ]);

    my($env_renewal) = $server_thread_renewal->join;

    is($env_renewal->{REQUEST_METHOD}, 'PATCH', 'Claim renewal uses PATCH method');
    is($env_renewal->{PATH_INFO}, '/v1/claims/abc', 'Claim renewal path');
    is_deeply($env_renewal->{__BODY__},
        { ttl => 1 },
        'Claim renewal body');

    my $server_thread_release = make_server_thread($server, [
        204, [], [], ]);

    ok($lock->release, 'Release lock');

    my($env_release) = $server_thread_release->join;
}


sub _new_http_server {
    my $socket = IO::Socket::INET->new(
        LocalAddr   => 'localhost',
        Proto       => 'tcp',
        Listen      => 5);

    my $server = HTTP::Server::PSGI->new(
        host => $socket->sockaddr,
        port => $socket->sockport,
        timeout => 120);

    $server->{listen_sock} = $socket;

    return ($server, $socket->sockhost, $socket->sockport);
}

sub _get_request_body {
    my ($psgi_input) = @_;

    my $body = '';
    while ($psgi_input->read($body, 1024, length($body))) {}

    return JSON::decode_json($body);
}
