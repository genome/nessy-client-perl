#!/usr/bin/env perl

use strict;
use warnings;

use Nessy::Claim;

use Test::More tests => 9;

test_failing_constructor();
test_release();
test_destructor();

sub test_failing_constructor {

    my $claim;

    $claim = eval { Nessy::Claim->new() };
    ok($@, 'new() with no args throws an exception');

    $claim = eval { Nessy::Claim->new(resource_name => 'foo') };
    like($@, qr(on_release is a required param), 'new() without on_release arg throws an exception');

    $claim = eval { Nessy::Claim->new(on_release => sub {} ) };
    like($@, qr(resource_name is a required param), 'new() without resource_name arg throws an exception');
}

sub test_release {
    my $resource_name = 'foo';

    my $on_release_called = 0;
    my $on_release = sub { $on_release_called++; 1 };
    my $claim = Nessy::Claim->new(resource_name => $resource_name, on_release => $on_release);
    ok($claim, 'Created Claim object');

    ok($claim->release(), 'release()');

    is($on_release_called, 1, 'on_release callback was called');

    undef($claim);

    is($on_release_called, 1, 'on_release callback was not called again');
}

sub test_destructor {
    my $resource_name = 'foo';

    my $on_release_called = 0;
    my $on_release = sub { $on_release_called++ };
    my $claim = Nessy::Claim->new(resource_name => $resource_name, on_release => $on_release);
    ok($claim, 'Created Claim object');


    undef($claim);

    is($on_release_called, 1, 'on_release called once in destructor');
}


