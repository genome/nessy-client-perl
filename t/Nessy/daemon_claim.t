#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Nessy::Daemon::Claim;

use Test::More;
use Test::MockObject;


subtest test_release => sub {
    my ($claim, $ci, $eg) = _create_objects();

    $claim->release;

    my ($method_name, $args) = $eg->next_call;

    is($method_name, 'release', 'release method called on event generator');
    is_deeply($args, [$eg, $ci], 'command interface passed to release method');
};


subtest test_start => sub {
    my ($claim, $ci, $eg) = _create_objects();

    $claim->start;

    my ($method_name, $args) = $eg->next_call;

    is($method_name, 'start', 'start method called on event generator');
    is_deeply($args, [$eg, $ci], 'command interface passed to start method');
};


subtest test_terminate => sub {
    my ($claim, $ci, $eg) = _create_objects();

    $claim->terminate;

    my ($method_name, $args) = $eg->next_call;

    is($method_name, 'signal', 'signal method called on event generator');
    is_deeply($args, [$eg, $ci], 'command interface passed to signal method');
};


subtest test_resource_name => sub {
    my ($claim, $ci, $eg) = _create_objects();

    $claim->resource_name;

    $ci->called_ok('resource', 'resource gotten from command_interface');
};


subtest test_validate => sub {
    my ($claim, $ci, $eg) = _create_objects();

    $claim->validate;

    $ci->called_ok('is_active', 'claim status checked via command_interface');
};


done_testing();


sub _create_objects {
    my $ci = Test::MockObject->new;
    $ci->set_true (
        'is_active',
        'resource',
    );

    my $eg = Test::MockObject->new;
    $eg->set_true(
        'release',
        'signal',
        'start',
    );

    my $claim = Nessy::Daemon::Claim->new(
        command_interface => $ci,
        event_generator => $eg,
    );

    return ($claim, $ci, $eg);
}
