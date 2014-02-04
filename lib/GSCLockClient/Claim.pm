package GSCLockClient::Claim;

use strict;
use warnings;

use GSCLockClient::Properties qw(resource_name keychain);

sub new {
    my ($class, %params) = @_;

    my $self = bless {}, $class;
    $self->resource_name($params{resource_name}) or die "resource_name is a required param for Claim";
    $self->keychain($params{keychain}) or die "keychain is a required param for Claim";

    return $self;
}

sub release {
    my $self = shift;
    return $self->keychain->release( $self->resource_name );
}

sub DESTROY {
    my $self = shift;
    $self->release;
}

1;
