package Nessy::Properties;

use strict;
use warnings;

use Sub::Install;
use Sub::Name;
use Carp;

our @CARP_NOT;
our %properties_for_class;

sub import {
    shift;  # throw away this package name
    my $package = caller();
    import_properties($package, @_);
}

sub import_properties {
    my $package = shift;

    push @CARP_NOT, $package;

    my @property_list = @_;
    $properties_for_class{$package} = \@property_list;

    foreach my $prop ( @property_list ) {
        my $sub = Sub::Name::subname $prop => _property_sub($prop);
        Sub::Install::install_sub({
            code => $sub,
            into => $package,
            as => $prop
        });
    }

    Sub::Install::install_sub({
        code => \&_verify_params,
        into => $package,
        as => '_verify_params',
    });

    my $property_names_sub = sub {
        my $class = shift;
        my @parent_classes = do {
                no strict 'refs';
                my $isa = "${class}::ISA";
                @$isa;
            };
        my @parent_props = map { $_->__property_names } @parent_classes;
        my @this_props = @{$properties_for_class{$package}};
        my %unduplicated_props = map { $_ => 1 } ( @parent_props, @this_props );
        return keys %unduplicated_props;
    };
    Sub::Install::install_sub({
        code => $property_names_sub,
        into => $package,
        as => '__property_names',
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

sub _verify_params {
    my($class, $params, @required) = @_;

    my %required = map { $_ => 1 } @required;
    my %verified_params;

    my @all_properties_for_class = $class->__property_names;
    foreach my $param_name ( @all_properties_for_class ) {
        if ($required{$param_name} and ! exists($params->{$param_name})) {
            Carp::croak("$param_name is a required param") unless exists ($params->{$param_name});
        }
        $verified_params{$param_name} = $params->{$param_name};
    }
    return \%verified_params;
}

1;
