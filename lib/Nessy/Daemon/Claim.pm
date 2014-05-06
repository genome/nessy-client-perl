package Nessy::Daemon::Claim;

use strict;
use warnings FATAL => 'all';

use Nessy::Properties qw(command_interface event_generator);


sub new {
    my $class = shift;
    my %params = @_;

    return bless $class->_verify_params(\%params, qw(
        command_interface
        event_generator
    )), $class;
}


sub release {
    my $self = shift;

    $self->event_generator->release($self->command_interface);

    1;
}

sub start {
    my $self = shift;

    $self->event_generator->start($self->command_interface);

    1;
}

sub shutdown {
    my $self = shift;

    $self->event_generator->shutdown($self->command_interface);
}

sub terminate {
    my $self = shift;

    $self->event_generator->signal($self->command_interface);

    1;
}


sub resource_name {
    my $self = shift;
    return $self->command_interface->resource;
}

sub validate {
    my ($self, $is_active_callback) = @_;

    return $self->command_interface->is_active($is_active_callback);
}


1;


=pod

=head1 NAME

Nessy::Daemon::Claim - Manage the state of a claim in the Daemon process

=head1 SYNOPSIS

  my $claim = Nessy::Daemon::Claim->new(
                resource_name => $resource_name_string,
                url => $server_url,
                api_version => $version_string,
                ttl => $claim_ttl_seconds,
                timeout => $command_timeout_seconds,
                user_data => $data_ref,
                on_fatal_error => $fatal_subref,
            );

  $claim->start();

  $claim->on_success_cb( $release_success_cb );
  $claim->on_fail_cb( $release_fail_subref );
  $claim->release;

  $claim->validate( sub {
        printf("Claim %s is %s\n",
                $claim->resource_name,
                shift ? "valid" : "not valid");
        });

=head1 DESCRIPTION

Nessy::Daemon::Claim instances manage the state of individual claims for the
Daemon process.  They're implemented as event-driven state machines.  After
a new instance is created, calling C<start()> puts the state machine into
motion by sending a registration request to the Nessy server.

=head1 CONSTRUCTOR

  my $claim = Nessy::Daemon::Claim->new( %params );

Instantiate a new Claim object.  Parameters are key/value pairs.  Newly created
Claim objects are in the C<STATE_NEW> state.

=head3 Required construction parameters

=over 2

=item url
                
The top-level URL of the Nessy server

=item resource_name

The resource name to claim

=item api_version

The dialect to use when talking to the Nessy server

=item ttl

The time in seconds to use for this claim's time-to-live.  The server
will expire the claim after the ttl expires.  The Claim state machine will
periodically send ttl updates when it is in the ACTIVE state, and so the
claim can persist for longer than any single ttl interval.

=item on_fatal_error

A code reference that will be called if the Claim enters an unrecoverable state.
This can happen if an exception is thrown during processing, if the server
sends an unexpected response, or if it gets a 400-type response when sending
a renewal (ttl update) indicating a claim we thought was valid is no longer
valid.

=back

=head3 Optional construction parameters

=over 2

=item user_data

A scalar value associated with the Claim.  This data is sent to but ignored by
the server,  This value must be serializable with the JSON module.

=item timeout

A duration in seconds specifying how long it should wait for a response from
the server before giving up.  After the timeout expires, the on_fail_cb
callback will be called.  The value C<undef> means it should wait forever
if necessary.

=back

=head2 Methods

=over 4

=item start( %params )

Start this Claim's state machine by sending a registration request to the
server.  C<%params> is a list of key/value pairs.  They are required.

=over 2

=item on_success

Sets the on_success_cb attribute that will be called if the claim succeeds.

=item on_fail

Sets the on_fail_cb attribute that will be called if the claim fails.

=back

=item release( %params )

Restarts the claim's state machine by sending a release request to the Nessy
server.  C<%params> is a list of key/value pairs.  They are required.

=item validate( $subref_callback )

Sends a renewal message to the server for this Claim.  The callback is called
with one argument indicating whether this Claim is valid or not.

=over 2

=item on_success

Sets the on_success_cb attribute that will be called if the release succeeds.

=item on_fail

Sets the on_fail_cb attribute that will be called if the release fails.

=back

=item resource_name()

Returns the resource_name set when the object was created

=item user_data()

Returns the user_data set when the object was created

=item url()

Returns the url set when the object was creates

=item ttl()

Returns the ttl set when the object was created

=item api_version()

Returns the api_version set when the object was created

=item on_fatal_error()

Returns the on_fatal_error set when the object was created

=item timeout()

Returns the timeout set when the object was created

=item claim_location_url()

Stores the claim-specific URL returned by the server when a claim is
successfully registered.

=item timer_watcher()

Stores an AnyEvent->timer() instance used to trigger the periodic activation
and renewal requests.

=item registration_timeout_watcher()

Stores an AnyEvent->timer() instance to implement the timeout behavior while
registering.

=item state()

Return the state of this Claim.  See below for a description of the valid
states.

=item on_success_cb()

Get or set the on_success_cb subref.

=item on_fail_cb()

Get or set the on_fail_cb subref.

=item 

=back

=head2 Internal Methods

The following methods are used internally by the Claim's state machine and
should not be called from the outside.

=over 4

=item send_register()

Starts the registration process by sending a POST request to /claims/.

=item recv_register_response_201

=item recv_register_response_202

=item recv_register_response_400

=item recv_register_response_5XX

Callbacks for when the registration response is received.  Each method's
suffix is the HTML response code.

=item recv_register_response_TIMEOUT

Called when a registeration request times out.

=item send_activation()

Sends an activation request to the server by sending a PATCH request to this
Claim's claim_location_url to change the status to "active"

=item recv_activating_response_200

=item recv_activating_response_409

=item recv_activating_response_5XX

=item recv_activating_response_400

=item recv_activating_response_404

Callbacks for each recognized response to the activation request.

=item send_renewal()

Sends a renewal request to the server by sending a PATCH request to this
Claim's claim_location_url to change the ttl back to the initial ttl.

=item recv_renewal_response_200

=item recv_renewal_response_4XX

=item recv_renewal_response_5XX

Callbacks for each recognized response to the renewal request.

=item recv_release_response_204

=item recv_release_response_400

=item recv_release_response_404

=item recv_release_response_409

=item recv_release_response_5XX

Callbacks for each recognized respose to the release request.

=back

=head2 Claim States

=over 2

=item STATE_NEW

A newly created  Nessy::Daemon::Claim

=item STATE_REGISTRTING

The Claim has sent a registration request but not received a response yet.
It will go to STATE_ACTIVE or STATE_WAITING depending on if the server
responds that we have locked the claim or not.

=item STATE_WAITING

The Claim is registered with the server, but is not yet locked.  It will
periodically send activation requests to the server.  It will go to
STATE_ACTIVATING when it's time to send the request.

=item STATE ACTIVATING

The Claim has sent an activation request but not received a response yet.
It will go to STATE_ACTIVE if the response indicates we have locked the
claim, and STATE_WAITING if not.

=item STATE_ACTIVE

The Claim is registered with the server and we hold the lock.  The Claim
will periodically send renewal requests to the server.  It will go to
STATE_RENEWING when it's time to send the renewal.  It will go to
STATE_RELEASING when the C<release()> method is called on the Claim.

=item STATE_RENEWING

The Claim has sent a renewal request to the server.  It will go to STATE_ACTIVE
if the server response is successful.

=item STATE_RELEASING

The Claim has sent a release request to the server.  It will go to
STATE_RELEASED if the request succeeds.

=item STATE_RELEASED

This claim is released.

=item STATE_FAILED

Most failure conditions set the claim to this state.

=back

=head1 SEE ALSO

L<Nessy::Client>, L<Nessy::Daemon>, L<Nessy::Claim>

=head1 LICENCE AND COPYRIGHT

Copyright (C) 2014 Washington University in St. Louis, MO.

This sofware is licensed under the same terms as Perl itself.
See the LICENSE file in this distribution.

=cut

