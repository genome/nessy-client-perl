package Nessy::Keychain::Message;

use strict;
use warnings;

use JSON qw();

# used for messages sent between the user/daemon socket

my @property_list;
BEGIN { @property_list = qw( resource_name data result error_message command ) }

use Nessy::Properties @property_list;

sub new {
    my $class = shift;
    my %params = @_;

    my $self = bless {}, $class;
    $self->_required_params(\%params, qw(resource_name command ));

    foreach my $accessor ( @property_list ) {
        $self->$accessor($params{$accessor}) if (exists $params{$accessor});
    }
    return $self;
}

my $json = JSON->new->convert_blessed(1);
sub from_json {
    my($class, $string) = @_;

    return $class->new( %{ $json->decode($string) });
}

sub TO_JSON {
    my $self = shift;
    my %copy = %$self;
    return \%copy;
}

1;
