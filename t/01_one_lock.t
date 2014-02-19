#!/usr/bin/env perl

use strict;
use warnings FATAL => qw(all);

use Test::More;
BEGIN {
    my $can_use_threads = eval 'use threads; 1';
    if ($can_use_threads) {
        plan tests => 10;
    }
    else {
        plan skip_all => 'Needs threaded perl';
    }
};


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

test_get_release();
#test_get_undef();

sub make_server_thread {
    my ($server, $response) = @_;

    my $server_thread = threads->create( sub {
        my $env;
        $server->run( sub {
            $env = shift;
            $env->{'psgix.harakiri.commit'} = 1;
            return $response;
        });
        return $env;
    });

    return ($server_thread);
}

sub test_get_release {
    my $resource_name = 'foo';
    my $user_data = { bar => 'stuff goes here' };

    my $server_thread_register = make_server_thread($server, [
        201, ['Location' => "$url/v1/claims/abc"], [], ]);

    my $lock = $client->claim($resource_name, $user_data);

    my $env_register = $server_thread_register->join;

    is($env_register->{REQUEST_METHOD}, 'POST',
        'Claim request should use POST method');

    is($env_register->{PATH_INFO}, '/v1/claims/',
        'Claim request should access /v1/claims/');

    my $json_ref = _get_request_body( $env_register->{'psgi.input'} );
    is_deeply($json_ref, {
        resource    => $resource_name,
        user_data   => $user_data,
        ttl         => $ttl,
    }, 'The request body should be well formed');

    ok($lock, 'Got lock foo');
    ok(not($lock->_is_released), 'Lock should be active');



    my $server_thread_release = make_server_thread($server, [
        204, [], [], ]);

    ok($lock->release, 'Release lock');

    my $env_release = $server_thread_release->join;

    is($env_release->{REQUEST_METHOD}, 'PATCH',
        'Claim release should use PATCH method');

    is($env_release->{PATH_INFO}, '/v1/claims/abc',
        'Claim releas should access /v1/claims/abc');

    my $json_ref_release = _get_request_body( $env_release->{'psgi.input'} );
    is_deeply($json_ref_release, {
        status      => 'released'
    }, 'The request body should be well formed');

    ok($lock->_is_released, 'Lock should be released');
}

sub test_get_undef {
    is_deeply($client->claim_names(), [], 'All locks released');
    my $lock = $client->claim('foo');

    ok($lock, 'Get lock foo');
    is($lock->state, 'active', 'lock is active');
    undef($lock);
    
    is_deeply($client->claim_names(), [], 'All locks released');
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
