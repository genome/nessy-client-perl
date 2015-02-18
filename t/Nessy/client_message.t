#!/usr/bin/env perl

use strict;
use warnings;

use Nessy::Client::Message;
use JSON;

use Test::More tests => 5;

subtest constructor => sub {
    plan tests => 3;

    my $m = Nessy::Client::Message->new(resource_name => 'foo', command => 'bar', serial => 1);
    ok($m, 'constructor');
    is($m->resource_name, 'foo', 'resource_name property');
    is($m->command, 'bar', 'command property');
};

subtest 'constructor and properties' => sub {
    plan tests => 6;

    my @construction_params = (resource_name => 'foo', command => 'bar', serial => 1);
    my @remaining_params = (args => 123, result => 'abc', error_message => 'hi');
    while (@remaining_params) {
        push(@construction_params, splice(@remaining_params, 0, 2));
        my %construction_params = @construction_params;
        my $params_count = scalar(keys %construction_params);

        my $m = Nessy::Client::Message->new( @construction_params );
        ok($m, "new() with $params_count properties");

        my $is_ok = 1;
        foreach my $key ( keys %construction_params ) {
            $is_ok = 0 if ($m->$key ne $construction_params{$key});
        }
        ok($is_ok, "accessor with $params_count properties");
    }
};

subtest 'failed constructor' => sub {
    plan tests => 4;

    my $m = eval { Nessy::Client::Message->new() };
    ok($@, 'new() throws exception with no args');

    my %all_params = (
            resource_name => 'foo',
            command => 'bar',
            serial => 123,
        );

    foreach my $omit ( keys %all_params ) {
        my %params = %all_params;
        delete $params{$omit};
        my $m = eval { Nessy::Client::Message->new( %params ) };
        like($@, qr($omit is a required param), "constructor fails when missing $omit");
    }
};

subtest encode => sub {
    plan tests => 4;

    my %params = (
        resource_name => 'foo',
        command => 'bar',
        args => {
            key1 => 'bob',
            key2 => 2,
            other => [ 1, 2, { foo => 'bar' } ],
        },
        result => 'hooray',
        serial => 1,
        error_message => 'nothing');

    my $m = Nessy::Client::Message->new(%params);

    my $json = JSON->new->convert_blessed(1);
    my $string = $json->encode($m);
    ok($string, 'json encode');
    like($string, qr(resource_name), 'encoded json includes "resource_name"');

    my $copy = Nessy::Client::Message->from_json( $string );
    ok($copy, 'from_json()');

    my $is_ok = 1;
    foreach my $key ( keys %params ) {
        $is_ok = 0 if ($m->$key ne $params{$key});
    }
    ok($is_ok, 'json copy succeeded');
};

subtest 'success/fail' => sub {
    plan tests => 16;

    my $m = Nessy::Client::Message->new( command => 'hi', resource_name => 'foo', serial => 1);
    ok($m, 'new message');
    ok($m->succeed, 'Set message successful');
    ok($m->is_succeeded, 'Message was successful');
    ok(! $m->is_failed, 'Message was not failed');

    ok(! eval { $m->succeed }, 'Could not change status after it was set');
    like($@, qr(Cannot set Message to succeeded), 'exception');

    ok(! eval { $m->fail }, 'Could not change status after it was set');
    like($@, qr(Cannot set Message to failed), 'exception');


    $m = Nessy::Client::Message->new( command => 'hi', resource_name => 'foo', serial => 1);
    ok($m, 'new message');
    ok($m->fail, 'Set message failed');
    ok(! $m->is_succeeded, 'Message was not successful');
    ok($m->is_failed, 'Message was failed');

    ok(! eval { $m->succeed }, 'Could not change status after it was set');
    like($@, qr(Cannot set Message to succeeded), 'exception');

    ok(! eval { $m->fail }, 'Could not change status after it was set');
    like($@, qr(Cannot set Message to failed), 'exception');
};
