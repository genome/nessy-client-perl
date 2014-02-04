#!/usr/bin/env perl

use strict;
use warnings FATAL => qw(all);

use Test::More;
use GSCLockClient;
use GSCLockClient::FakeServer;

my $server = GSCLockClient::FakeServer->new();
my $manager = GSCLockClient->new( url => $server->url);
test_get_release();
test_get_under();

sub test_get_release {
    is_deeply($manager->claim_names(), [], 'Manager says we have no locks');

    my $lock = $manager->claim('foo');
    ok($lock, 'Got lock foo');
    is($lock->state, 'active', 'lock is active');
    is_deeply($manager->claim_names(), ['foo'], 'Manager says we have lock foo');

    ok($lock->release, 'Release lock');
    is($lock->state, 'released', 'Lock is released');

    is_deeply($manager->claim_names(), [], 'All locks released');
}

sub test_get_undef {
    is_deeply($manager->claim_names(), [], 'All locks released');
    my $lock = $manager->claim('foo');

    ok($lock, 'Get lock foo');
    is($lock->state, 'active', 'lock is active');
    undef($lock);
    
    is_deeply($manager->claim_names(), [], 'All locks released');
}

