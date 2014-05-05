#!/usr/bin/env perl

use strict;
use warnings FATAL => qw(all);

use Nessy::Client;
use Test::More;

unless ($ENV{NESSY_SERVER_URL}) {
    plan skip_all => 'Needs nessy-server for testing; '
        .' set NESSY_SERVER_URL to something like http://127.0.0.1/';
}


subtest get_and_release_claim => sub {
    my $client = _get_client();
    my $resource = _get_resource();
    my $claim = $client->claim($resource);
    ok($claim, 'got claim');

    ok($claim->release, 'released claim');
};


subtest ttl_shorter_than_lock_duration => sub {
    my $client = _get_client();
    my $resource = _get_resource();
    my $claim = $client->claim($resource, ttl => 2);
    ok($claim, 'got claim');

    sleep 5;

    ok($claim->validate, 'validated claim');
    ok($claim->release, 'released claim');
};


subtest claim_returns_false_with_contention_and_timeout => sub {
    plan tests => 4;
    my $resource = _get_resource();

    my $first_client = _get_client();
    my $first_claim = $first_client->claim($resource);
    ok($first_claim, 'got claim');

    my $second_client = _get_client();
    ok(!$second_client->claim($resource, timeout => 2),
        'second claim failed');

    ok($first_claim->validate, 'validated claim');
    ok($first_claim->release, 'released claim');
};


subtest failed_claim_does_not_block_new_claims => sub {
    plan tests => 5;

    my $resource = _get_resource();

    my $first_client = _get_client();
    my $second_client = _get_client();
    my $third_client = _get_client();

    my $first_claim = $first_client->claim($resource);
    ok($first_claim, 'got claim');

    ok(!$second_client->claim($resource, timeout => 2),
        'second claim failed');

    ok($first_claim->validate, 'validated claim');
    ok($first_claim->release, 'released claim');
    my $third_claim = $third_client->claim($resource,
        timeout => 2);

    ok($third_claim, 'third claim got resource');
};


subtest validate_active_claim_succeeds => sub {
    my $resource = _get_resource();
    my $client = _get_client();

    my $claim = $client->claim($resource);

    ok($claim->validate, 'active claim validates');
};


subtest validate_released_claim_fails => sub {
    my $resource = _get_resource();
    my $client = _get_client();

    my $claim = $client->claim($resource);

    $claim->release;
    ok(!$claim->validate, 'released claim fails to validate');
};


done_testing();


sub rndStr{ join'', @_[ map{ rand @_ } 1 .. shift ] }
sub _get_resource {
    return rndStr 20, 'A'..'Z', 'a'..'z', 0..9, '-', '_', '.';
};

sub _get_client {
    return Nessy::Client->new(url => $ENV{NESSY_SERVER_URL});
}
