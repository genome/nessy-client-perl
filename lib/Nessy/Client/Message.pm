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

=pod

=head1 NAME

Nessy::Client::Message - Transport messages between Nessy::Client and Nessy::Daemon

=head1 DESCRIPTION

Nessy::Client::Message instances are not used directly in a client program, but
are created by Nessy::Client and Nessy::Daemon to talk to each other.

The Client will create Message objects to request commands be performed by
the Daemon.  The Message is serialized with JSON and sent to the Daemon over
their communication socket.  The Daemon performs the action, sets the Message
as successful or failed, and sends back a message with the same serial,
filling in the error_message property if there was an exception.

=head1 CONSTRUCTOR

  my $message = Nessy::Client::Message->new(
                    resource_name => 'scarce_resource',
                    command => 'claim',
                    args => { user_data => 'secret', ttl => 321, timeout => 99 },
                    serial => 123 );

A Message instance essentially represents an RPC request.  resource_name,
command and serial are required arguments to the constructor.

  my $message = Nessy::Client::Message->from_json( $json_string )

Creates a Message instance from a JSON string.  This is used to deserialize
the message.

=head2 Methods

=over 2

=item resource_name()

Returns the resource_name set when the object was created

=item command()

Returns the command set when the object was created

=item serial()

Returns the serial set when the object was created

=item error_message()

=item error_message( $exception_message )

Get or set the error_message attribute

=item is_succeeded()

Returns true if this Message has gotten a response and it was successful.

=item success()

Mark this message as successful.  C<is_succeeded> will now return true.

=item is_failed()

Returns true if this Message has gotten a response and it failed.

=item fail()

Mark this message as failed.  C<is_failed> will now return true.

=back

=head1 SEE ALSO

L<Nessy::Claim>, L<Nessy::Daemon>

=head1 LICENCE AND COPYRIGHT

Copyright (C) 2014 Washington University in St. Louis, MO.

This sofware is licensed under the same terms as Perl itself.
See the LICENSE file in this distribution.

=cut

