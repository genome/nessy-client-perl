#!/usr/bin/env perl

use strict;
use warnings FATAL => qw(all);

use Nessy::Client;
use Sys::Hostname qw(hostname);
use Test::More;
use Time::HiRes qw(gettimeofday);


my $url;
my $ttl = 7;
if ($ENV{NESSY_SERVER_URL}) {
    plan tests => 1;
    $url = $ENV{NESSY_SERVER_URL};
}
else {
    plan skip_all => 'Needs nessy-server for testing; '
        .' set NESSY_SERVER_URL to something like http://127.0.0.1/';
}

test_get_release();

sub test_get_release {
    my $client = Nessy::Client->new( url => $url, default_ttl => $ttl);
    my ($resource_name, $user_data) = get_resource_and_user_data();
    my $lock   = $client->claim($resource_name,
        user_data => $user_data);
    ok($lock, "Got lock for $resource_name");
    ok(! $lock->_is_released, 'Lock should be active');
    ok($lock->release, 'Release should succeed');
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
