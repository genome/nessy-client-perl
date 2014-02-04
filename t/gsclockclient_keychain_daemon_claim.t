#!/usr/bin/env perl

use strict;
use warnings;

use GSCLockClient::Keychain::Daemon::Claim;

use JSON;
use Test::More tests => 10;

test_failed_constructor();
test_constructor();

sub test_failed_constructor {

    my $claim;

    $claim = eval { GSCLockClient::Keychain::Daemon::Claim->new() };
    ok($@, 'Calling new() without args throws an exception');

    my %all_params = (
            url => 'http://test.org',
            resource_name => 'foo',
            keychain => 'bar',
        );
    foreach my $missing_arg ( keys %all_params ) {
        my %args = %all_params;
        delete $args{$missing_arg};

        $claim = eval { GSCLockClient::Keychain::Daemon::Claim->new( %args ) };
        like($@,
            qr($missing_arg is a required param),
            "missing arg $missing_arg throws an exception");
    }
}

sub test_constructor {
    my $claim;
    my $keychain = GSCLockClient::Keychain::Daemon::Fake->new();

    my $url = 'http://example.org';
    my $resource_name => 'foo';
    $claim = GSCLockClient::Keychain::Daemon::TestClaim->new(
                url => $url,
                resource_name => $resource_name,
                keychain => $keychain
            );
    ok($claim, 'Create Claim');

    my $params = $claim->_http_post_params();
    is(scalar(@$params), 1, 'Sent 1 http post');

    my $json = JSON->new();
    my $got_url = shift @{$params->[0]};
    is($got_url, "${url}/claims", 'post URL param');

    my $got_body = $json->decode(shift @{$params->[0]});
    is_deeply($got_body,
            { resource => $resource_name },
            'post body param');

    my $got_cb = pop @{$params->[0]};
    is(ref($got_cb), 'CODE', 'Callback set in post params');

    is_deeply($params->[0],
              [ 'Content-Type' => 'application/json' ],
              'headers in http post');
}


package GSCLockClient::Keychain::Daemon::TestClaim;
BEGIN {
    our @ISA = qw( GSCLockClient::Keychain::Daemon::Claim );
}

sub _send_http_post {
    my $self = shift;
    my @params = @_;

    $self->{_http_post_params} ||= [];
    push @{$self->{_http_post_params}}, \@params;
}

sub _http_post_params {
    return shift->{_http_post_params};
}


package GSCLockClient::Keychain::Daemon::Fake;
sub new {
    my $class = shift;
    return bless {}, $class;
}

sub claim_failed {

}

sub claim_succeeded {

}



