package GSCLockClient::Claim;

use strict;
use warnings;

use GSCLockClient::Properties qw(resource_name keychain _is_released);

sub new {
    my ($class, %params) = @_;

    my $self = bless {}, $class;
    $self->resource_name($params{resource_name}) or die "resource_name is a required param for Claim";
    $self->keychain($params{keychain}) or die "keychain is a required param for Claim";

    return $self;
}

sub release {
    my $self = shift;
    return if $self->_is_released();
    return unless $self->keychain;

    my $rv =  $self->keychain->release( $self->resource_name );
    $self->_is_released(1);
    return $rv;
}

sub DESTROY {
    my $self = shift;
    $self->release;
}

1;
