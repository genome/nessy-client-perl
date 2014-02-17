package Nessy::Claim;

use strict;
use warnings;

use Nessy::Properties qw(resource_name on_release _is_released);

sub new {
    my ($class, %params) = @_;

    my $self = $class->_verify_params(\%params, qw(resource_name on_release));
    return bless $self, $class;
}

sub release {
    my $self = shift;
    return if $self->_is_released();
    $self->_is_released(1);

    $self->on_release->(@_);
}

sub DESTROY {
    my $self = shift;
    $self->release;
}

1;
