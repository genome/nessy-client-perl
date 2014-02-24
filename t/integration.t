#!/usr/bin/env perl

use strict;
use warnings FATAL => qw(all);

use Nessy::Client;
use Sys::Hostname qw(hostname);
use Test::More;
use Time::HiRes qw(gettimeofday);

use lib 't/lib';
use Nessy::Client::TestWebProxy;

if ($ENV{NESSY_SERVER_URL}) {
    plan tests => 4;
}
else {
    plan skip_all => 'Needs nessy-server for testing; '
        .' set NESSY_SERVER_URL to something like http://127.0.0.1/';
}

my $ttl = 7;

test_get_release();

sub test_get_release {
    my $proxy = Nessy::Client::TestWebProxy->new($ENV{NESSY_SERVER_URL});

    local $ENV{NESSY_CLIENT_PROXY} = $proxy->url;
    my $client = Nessy::Client->new( url => $ENV{NESSY_SERVER_URL},
        default_ttl => $ttl);
    my ($resource_name, $user_data) = get_resource_and_user_data();

    my $claim_condvar = AnyEvent->condvar;
    $client->claim($resource_name,
        user_data => $user_data, cb => $claim_condvar);

    my ($register_req, $register_res) = $proxy->do_one_request;
    my $lock = $claim_condvar->recv;
    ok($lock, "Got lock for $resource_name");
    ok(! $lock->_is_released, 'Lock should be active');

    my $release_condvar = AnyEvent->condvar;
    $lock->release($release_condvar);
    $proxy->do_one_request;
    ok($release_condvar->recv, 'Release should succeed');
    ok($lock->_is_released, 'Lock should be released');
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
