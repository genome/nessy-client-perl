package Nessy::Properties;

use strict;
use warnings;

use Sub::Install;
use Sub::Name;
use Carp;

our @CARP_NOT;

sub import {
    my $package = caller();

    push @CARP_NOT, $package;

    foreach my $prop ( @_ ) {
        my $sub = Sub::Name::subname $prop => _property_sub($prop);
        Sub::Install::install_sub({
            code => $sub,
            into => $package,
            as => $prop
        });
    }

    Sub::Install::install_sub({
        code => \&_required_params,
        into => $package,
        as => '_required_params',
    });
}

sub _property_sub {
    my($prop_name) = @_;

    return sub {
        my $self = shift;
        if (@_) {
            $self->{$prop_name} = shift;
        }
        return $self->{$prop_name};
    };
}

sub _required_params {
    my($self, $params, @required) = @_;

    my %verified_params;
    foreach my $param_name ( @required ) {
        Carp::croak("$param_name is a required param") unless exists ($params->{$param_name});
        $self->$param_name( $params->{$param_name} ) if (ref $self);
        $verified_params{$param_name} = $params->{$param_name};
    }
    return \%verified_params;
}

1;
