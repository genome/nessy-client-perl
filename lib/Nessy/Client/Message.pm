package Nessy::Client::Message;

use strict;
use warnings;

use JSON qw();

# used for messages sent between the user/daemon socket

use Nessy::Properties qw( resource_name args result error_message command serial );

sub new {
    my $class = shift;
    my %params = @_;

    my $self = $class->_verify_params(\%params, qw(resource_name command serial ));

    return bless $self, $class;
}

sub succeed {
    my $self = shift;
    if ($self->result) {
        Carp::croak('Cannot set Message to succeeded; it already has result status '.$self->result);
    }
    $self->result('succeeded');
}

sub is_succeeded {
    return shift->result eq 'succeeded';
}

sub fail {
    my $self = shift;
    if ($self->result) {
        Carp::croak('Cannot set Message to failed; it already has result status '.$self->result);
    }
    $self->result('failed');
}

sub is_failed {
    return shift->result eq 'failed';
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
