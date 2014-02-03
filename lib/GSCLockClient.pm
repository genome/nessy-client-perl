package GSCLockClient;

use strict;
use warnings;

use GSCLockClient::Properties qw(url ttl timeout api_version keychain claims);
use GSCLockClient::Keychain;
use GSCLockClient::Claim;

sub new {
    my($class, %params) = @_;

    my $self = bless {}, $class;
    $self->claims([]);

    unless ($self->url($params{url})) {
        die "new() requires a 'url parameter";
    }

    $self->ttl( $params{ttl} || $self->_default_ttl);
    $self->timeout( $params{timeout} || $self->_default_timeout);
    $self->api_version( $params{api_version} || $self->_default_api_version);

    my $keychain = GSCLockClient::Keychain->new(url => $self->url);
    die "Unable to create keychain" unless $keychain;
    $self->keychain( $keychain );

    return $self;
}

sub _default_ttl { 60 } # seconds
sub _default_timeout { 3600 }
sub _default_api_version { 'v1' }


sub claim {
    my($self, $resource_name) = @_;

    return $self->keychain->claim($resource_name);
}

sub claim_names {
    my $self = shift;

    my @names = map { $_->name } @{$self->claims };
    return @names;
}

sub DESTROY {
    my $self = shift;

    foreach my $claim ( @{$self->claims} ) {
        $claim->release;
    }

    $self->keychain && $self->keychain->shutdown;
}

1;
