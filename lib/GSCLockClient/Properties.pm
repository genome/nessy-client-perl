package GSCLockClient::Properties;

use Sub::Install;
use Sub::Name;

sub import {
    my $package = caller();

    foreach my $prop ( @_ ) {
        my $sub = Sub::Name::subname $prop => _property_sub($prop);
        Sub::Install::install_sub({
            code => $sub,
            into => $package,
            as => $prop
        });
    }
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

1;
