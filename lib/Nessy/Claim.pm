package Nessy::Claim;

use strict;
use warnings;

use Nessy::Properties qw(resource_name keychain _is_released);

sub new {
    my ($class, %params) = @_;

    my $self = $class->_required_params(\%params, qw(resource_name keychain));
    return bless $self, $class;
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
