#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 4;

subtest 'property names' => sub {
    plan tests => 1;

    my @properties = sort Nessy::Test::Class->__property_names();
    is_deeply(\@properties, [ qw(prop_a prop_b) ], '__property_names()');
};

subtest constructor => sub {
    plan tests => 2;

    my $obj = eval { Nessy::Test::Class->new() };
    ok(! $obj, 'constructor fails with no params');
    like($@, qr(prop_a is a required param), 'Exception');
};

subtest create => sub {
    plan tests => 3;

    my $obj = Nessy::Test::Class->new(prop_a => 1);
    ok($obj, 'Created object with required param');
    is($obj->prop_a, 1, 'prop_a');
    is($obj->prop_b, undef, 'prop_b');
};

subtest params => sub {
    plan tests => 6;

    my %obj1_params = (prop_a => 'a', prop_b => 'b');
    my %obj2_params = (prop_a => 1, prop_b => 2);
    my $obj1 = Nessy::Test::Class->new(%obj1_params);
    ok($obj1, 'Create test instance 1');

    my $obj2 = Nessy::Test::Class->new(%obj2_params);
    ok($obj2, 'Create test instance 2');

    my $check_params = sub {
        my($obj, $expected) = @_;
        foreach my $k ( keys %$expected ) {
            is($obj->$k, $expected->{$k}, "property $k is ".$expected->{$k});
        }
    };

    $check_params->($obj1, \%obj1_params);
    $check_params->($obj2, \%obj2_params);
};

package Nessy::Test::Class;

use Nessy::Properties qw(prop_a prop_b);

sub new {
    my $class = shift;
    my(%properties) = @_;

    my $self = $class->_verify_params(\%properties, qw(prop_a));

    return bless $self, $class;
}
