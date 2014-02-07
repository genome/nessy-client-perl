#!/usr/bin/env perl

use strict;
use warnings;

use Nessy::Claim;

use Test::More tests => 11;

test_failing_constructor();
test_release();
test_destructor();

sub test_failing_constructor {

    my $claim;

    $claim = eval { Nessy::Claim->new() };
    ok($@, 'new() with no args throws an exception');

    $claim = eval { Nessy::Claim->new(resource_name => 'foo') };
    like($@, qr(keychain is a required param), 'new() without keychain arg throws an exception');

    $claim = eval { Nessy::Claim->new(keychain => 'foo') };
    like($@, qr(resource_name is a required param), 'new() without resource_name arg throws an exception');
}

sub test_release {
    my $resource_name = 'foo';

    my $keychain = Nessy::FakeKeychain->new();

    my $claim = Nessy::Claim->new(resource_name => $resource_name, keychain => $keychain);
    ok($claim, 'Created Claim object');

    ok($claim->release(), 'release()');

    is($keychain->released_resource, $resource_name, 'Keychain release() called with correct args');
    is($keychain->release_count, 1, 'Keychain release() called 1 time');

    undef($claim);

    is($keychain->release_count, 1, 'Keychain release() not called again in destructor');
}

sub test_destructor {
    my $resource_name = 'foo';

    my $keychain = Nessy::FakeKeychain->new();

    my $claim = Nessy::Claim->new(resource_name => $resource_name, keychain => $keychain);
    ok($claim, 'Created Claim object');


    undef($claim);

    is($keychain->released_resource, $resource_name, 'Keychain release() called with correct args after destructor');
    is($keychain->release_count, 1, 'Keychain release() called once in destructor');
}


package Nessy::FakeKeychain;

sub new {
    my $class = shift;
    return bless {}, $class;
}

sub released_resource {
    return shift->{released};
}

sub release_count {
    return shift->{release_count} ||= 0;
}

sub release {
    my($self, $resource_name) = @_;
    $self->{released} = $resource_name;

    $self->{release_count} ||= 0;
    ++$self->{release_count};
}

