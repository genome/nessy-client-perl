#!/usr/bin/env perl

use strict;
use warnings;

use Nessy::Claim;

use Test::More tests => 17;

test_failing_constructor();
test_release();
test_destructor();
test_validate();

sub test_failing_constructor {

    my $claim;

    $claim = eval { Nessy::Claim->new() };
    ok($@, 'new() with no args throws an exception');

    my %all_params = ( resource_name => 'foo',
                       on_release => sub {},
                       on_validate => sub {} );

    foreach my $omit ( keys %all_params ) {
        my %params = %all_params;
        delete $params{$omit};
        $claim = eval { Nessy::Claim->new(%params) };
        ok(! $claim, "omitting $omit param does not return new object");
        like($@, qr($omit is a required param), "new() without $omit throws expected exception");
    }
}

sub test_release {
    my $resource_name = 'foo';

    my($on_release_called, $on_validate_called) = (0, 0);
    my $on_release = sub { $on_release_called++; 1 };
    my $on_validate = sub { $on_validate_called++; 1 };
    my $claim = Nessy::Claim->new(resource_name => $resource_name, on_release => $on_release, on_validate => $on_validate);
    ok($claim, 'Created Claim object');

    ok($claim->release(), 'release()');

    is($on_release_called, 1, 'on_release callback was called');
    is($on_validate_called, 0, 'on_validate callback was not called');

    undef($claim);

    is($on_release_called, 1, 'on_release callback was not called again');
    is($on_validate_called, 0, 'on_validate callback was not called');
}

sub test_destructor {
    my $resource_name = 'foo';

    my $on_release_called = 0;
    my $on_release = sub { $on_release_called++ };
    my $claim = Nessy::Claim->new(resource_name => $resource_name, on_release => $on_release, on_validate => sub {});
    ok($claim, 'Created Claim object');


    undef($claim);

    is($on_release_called, 1, 'on_release called once in destructor');
}

sub test_validate {
    my $on_validate_called = 0;
    my $on_validate = sub { $on_validate_called++; 1};
    my $claim = Nessy::Claim->new(resource_name => 'foo', on_release => sub {}, on_validate => $on_validate);

    ok($claim->validate, 'on_validate');
    is($on_validate_called, 1, 'on_validate callback was called');
}


