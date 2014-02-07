#!/usr/bin/env perl

use strict;
use warnings;

use Nessy::Keychain::Message;
use JSON;

use Test::More tests => 16;

test_constructor();
test_constructor_and_properties();
test_failed_constructor();

test_encode();


sub test_constructor {
    my $m = Nessy::Keychain::Message->new(resource_name => 'foo', command => 'bar');
    ok($m, 'constructor');
    is($m->resource_name, 'foo', 'resource_name property');
    is($m->command, 'bar', 'command property');
}

sub test_constructor_and_properties {

    my @construction_params = (resource_name => 'foo', command => 'bar');
    my @remaining_params = (data => 123, result => 'abc', error_message => 'hi');
    while (@remaining_params) {
        push(@construction_params, splice(@remaining_params, 0, 2));
        my %construction_params = @construction_params;
        my $params_count = scalar(keys %construction_params);

        my $m = Nessy::Keychain::Message->new( @construction_params );
        ok($m, "new() with $params_count properties");

        my $is_ok = 1;
        foreach my $key ( keys %construction_params ) {
            $is_ok = 0 if ($m->$key ne $construction_params{$key});
        }
        ok($is_ok, "accessor with $params_count properties");
    }
}

sub test_failed_constructor {
    my $m = eval { Nessy::Keychain::Message->new() };
    ok($@, 'new() throws exception with no args');

    $m = eval { Nessy::Keychain::Message->new(resource_name => 'foo') };
    like($@, qr(command is a required param), 'constructor fails when missing command');

    $m = eval { Nessy::Keychain::Message->new(command => 'bar') };
    like($@, qr(resource_name is a required param), 'constructor fails when missing resource_name');
}

sub test_encode {
    my %params = (
        resource_name => 'foo',
        command => 'bar',
        data => {
            key1 => 'bob',
            key2 => 2,
            other => [ 1, 2, { foo => 'bar' } ],
        },
        result => 'hooray',
        error_message => 'nothing');

    my $m = Nessy::Keychain::Message->new(%params);

    my $json = JSON->new->convert_blessed(1);
    my $string = $json->encode($m);
    ok($string, 'json encode');
    like($string, qr(resource_name), 'encoded json includes "resource_name"');

    my $copy = Nessy::Keychain::Message->from_json( $string );
    ok($copy, 'from_json()');

    my $is_ok = 1;
    foreach my $key ( keys %params ) {
        $is_ok = 0 if ($m->$key ne $params{$key});
    }
    ok($is_ok, 'json copy succeeded');
}
