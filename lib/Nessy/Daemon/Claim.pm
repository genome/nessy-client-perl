package Nessy::Daemon::Claim;

use strict;
use warnings;

use Nessy::Properties qw(
            resource_name user_data state url claim_location_url timer_watcher ttl api_version
            on_success_cb on_fail_cb on_fatal_error timeout registration_timeout_watcher);

use AnyEvent;
use AnyEvent::HTTP;
use JSON;
use Data::Dumper;
use Scalar::Util qw();
use Sub::Name;
use Sub::Install;

use constant STATE_NEW          => 'new';
use constant STATE_REGISTERING  => 'registering';
use constant STATE_WAITING      => 'waiting';
use constant STATE_ACTIVATING   => 'activating';
use constant STATE_ACTIVE       => 'active';
use constant STATE_RENEWING     => 'renewing';
use constant STATE_RELEASED     => 'released';
use constant STATE_RELEASING    => 'releasing';
use constant STATE_FAILED       => 'failed';

my %STATE = (
    STATE_NEW()         => [ STATE_REGISTERING, STATE_RELEASED ],
    STATE_REGISTERING() => [ STATE_WAITING, STATE_ACTIVE ],
    STATE_WAITING()     => [ STATE_ACTIVATING ],
    STATE_ACTIVATING()  => [ STATE_ACTIVE, STATE_WAITING ],
    STATE_ACTIVE()      => [ STATE_RENEWING, STATE_RELEASING ],
    STATE_RELEASING()   => [ STATE_RELEASED ],
    STATE_RENEWING()    => [ STATE_ACTIVE ],
    STATE_FAILED()      => [],
    STATE_RELEASED()    => [],
);


my $json_parser;
sub json_parser {
    $json_parser ||= JSON->new();
}

sub new {
    my($class, %params) = @_;

    $class->_set_proxy();

    my $self = $class->_verify_params(\%params, qw(url resource_name ttl on_fatal_error api_version));

    if (defined($self->{timeout}) and $self->{timeout} <= 0) {
        Carp::croak("timeout must be undef or a positive number");
    }

    bless $self, $class;
    $self->state(STATE_NEW);
    return $self;
}

my $proxy_already_set = 0;
sub _set_proxy {
    return if $proxy_already_set;

    $proxy_already_set = 1;
    if ($ENV{NESSY_CLIENT_PROXY}) {
        AnyEvent::HTTP::set_proxy($ENV{NESSY_CLIENT_PROXY});
    }
}

sub start {
    my $self = shift;
    my(%params) = @_;

    $self->on_success_cb($params{on_success}) || Carp::croak('on_success is required');
    $self->on_fail_cb($params{on_fail}) || Carp::croak('on_fail is required');

    $self->send_register();
}

sub transition {
    my($self, $new_state) = @_;

    my @allowed_next = @{ $STATE{ $self->state } };
    foreach my $allowed_next ( @allowed_next ) {
        if ($allowed_next eq $new_state) {
            $self->state($new_state);
            return 1;
        }
    }
    $self->send_fatal_error(Carp::shortmess("Illegal transition from ".$self->state." to $new_state"));
}

sub _call_success_fail_callback {
    my($self, $callback_name, @args) = @_;

    my $cb = $self->$callback_name;

    $self->on_fail_cb(undef);
    $self->on_success_cb(undef);

    $self->$cb(@args);
}

sub _claim_failure_generator {
    my($class, $error) = @_;

    return sub {
        my $self = shift;
        my ($body, $headers) = @_;

        $self->_remove_all_watchers();
        $self->state(STATE_FAILED);
        $self->_call_success_fail_callback('on_fail_cb',
            join ': ', $headers->{Status}, $error);

        1;
    };
}

sub _release_failure_generator {
    my($class, $error) = @_;

    return sub {
        my $self = shift;
        $self->_remove_all_watchers();
        $self->state(STATE_FAILED);
        $self->_call_success_fail_callback('on_fail_cb', $error);
        1;
    };
}

sub send_register {
    my $self = shift;
    $self->transition(STATE_REGISTERING);

    my $responder = $self->_make_response_generator(
                        'claim',
                        'recv_register_response');

    my $request_body = {
        resource => $self->resource_name,
        ttl => $self->ttl};

    $request_body->{user_data} = $self->user_data
        if defined $self->user_data;


    if ($self->timeout) {
        my $request_watcher = $self->_send_http_request(
                POST => $self->url . '/' . $self->api_version . '/claims/',
                headers => {'Content-Type' => 'application/json'},
                body => $self->json_parser->encode($request_body),
                $responder,
            );

        my $timed_out_registering = $self->_registration_timeout_handler($responder, $request_watcher);
        my $timer_watcher = $self->_create_timer_event(
                                    after => $self->timeout,
                                    cb => $timed_out_registering,
                            );
        $self->registration_timeout_watcher($timer_watcher);
    } else {
        $self->_send_http_request(
            POST => $self->url . '/' . $self->api_version . '/claims/',
            headers => {'Content-Type' => 'application/json'},
            body => $self->json_parser->encode($request_body),
            $responder,
        );
    }
}

sub _registration_timeout_handler {
    my($self, $responder, $request_watcher) = @_;
    return sub {
        undef $request_watcher;
        $responder->('', { Status => 'TIMEOUT' });
        1;
    };
}

sub _send_http_request {
    my $self = shift;
    my $method = shift;
    my $url = shift;

    AnyEvent::HTTP::http_request(
        $method => $url,
        timeout => $self->_default_http_timeout_seconds, @_);
}

sub _response_status {
    my($self, $headers) = @_;
    return $headers->{Status};
}

sub _make_response_generator {
    my ($self, $command, $prefix) = @_;

    my $sub = sub {
        my($body, $headers) = @_;

        my $status = $self->_response_status($headers);
        my $status_class = substr($status,0,1);

        my $coderef = $self->can("${prefix}_${status}")
            || $self->can("${prefix}_${status_class}XX");

        unless (my $rv = eval { $coderef && $self->$coderef($body, $headers); }) {
            unless (defined $rv) {
                $rv = '(undef)';
            }
            $self->send_fatal_error(
                "Error when handling status $status"
                    ." in ${prefix} for $command. returned: $rv\n\texception: $@\n"
                    . "Headers: " . Data::Dumper::Dumper($headers) ."\n"
                    . "Body: " . Data::Dumper::Dumper($body));
            return 0;
        }
        return 1;
    };
    return $sub;
}

sub _install_sub {
    my($name, $sub) = @_;
    Sub::Name::subname $name, $sub;
    Sub::Install::install_sub({
        code => $sub,
        as => $name,
        into => __PACKAGE__
    });
}

sub recv_register_response_201 {
    my($self, $body, $headers) = @_;
    $self->claim_location_url( $headers->{location} );
    $self->_successfully_activated();
}

sub _successfully_activated {
    my $self = shift;

    $self->registration_timeout_watcher(undef);

    $self->transition(STATE_ACTIVE);

    my $ttl = $self->_ttl_timer_value;
    my %params = (
        after => $ttl,
        cb => sub { $self->send_renewal() });

    if ($ttl > 0) {
        $params{interval} = $ttl;
    }

    my $w = $self->_create_timer_event(%params);
    $self->timer_watcher($w);
    $self->_call_success_fail_callback('on_success_cb');
    1;
}

sub recv_register_response_202 {
    my($self, $body, $headers) = @_;

    $self->transition(STATE_WAITING);

    $self->claim_location_url( $headers->{location} );
    my $ttl = $self->_ttl_timer_value;
    my $w = $self->_create_timer_event(
                after => $ttl,
                interval => $ttl,
                cb => sub { $self->send_activating() }
            );
    $self->timer_watcher($w);
}

_install_sub('recv_register_response_TIMEOUT', __PACKAGE__->_claim_failure_generator('timeout expired'));
_install_sub('recv_register_response_400', __PACKAGE__->_claim_failure_generator('bad request'));
_install_sub('recv_register_response_5XX', __PACKAGE__->_claim_failure_generator('server error'));

sub send_activating {
    my $self = shift;
    $self->transition(STATE_ACTIVATING);

    my $responder = $self->_make_response_generator(
                        'claim',
                        'recv_activating_response');
    $self->_send_http_request(
        PATCH => $self->claim_location_url,
        headers => {'Content-Type' => 'application/json'},
        timeout => ($self->_ttl_timer_value / 2),
        body => $self->json_parser->encode({ status => 'active' }),
        $responder,
    );
}

sub recv_activating_response_409 {
    my($self, $body, $headers) = @_;

    $self->transition(STATE_WAITING);
}

sub recv_activating_response_200 {
    my($self, $body, $headers) = @_;

    $self->_successfully_activated();
}

sub recv_activating_response_5XX {
    my($self, $body, $headers) = @_;
    $self->transition(STATE_WAITING);
    return 1;
}

_install_sub('recv_activating_response_400', __PACKAGE__->_claim_failure_generator('activating: bad request'));
_install_sub('recv_activating_response_404', __PACKAGE__->_claim_failure_generator('activating: non-existent claim'));

sub send_renewal {
    my $self = shift;
    $self->transition(STATE_RENEWING);

    my $responder = $self->_make_response_generator(
                        'renew',
                        'recv_renewal_response');
    $self->_send_renewal_request($responder);
}


sub _send_renewal_request {
    my($self, $responder) = @_;

    $self->_send_http_request(
        PATCH => $self->claim_location_url,
        headers => {'Content-Type' => 'application/json'},
        timeout => ($self->_ttl_timer_value / 2),
        body => $self->json_parser->encode({ ttl => $self->ttl }),
        $responder);
}

sub recv_renewal_response_200 {
    my($self, $body, $headers) = @_;
    $self->transition(STATE_ACTIVE);
    return 1;
}

sub recv_renewal_response_4XX {
    my($self, $body, $headers) = @_;
    $self->state(STATE_FAILED);

    my $status = $headers->{Status};
    $self->send_fatal_error(
        'claim '.$self->resource_name." failed renewal with code $status");
    return 1;
}

sub recv_renewal_response_5XX {
    my($self, $body, $headers) = @_;
    $self->transition(STATE_ACTIVE);
    return 1;
}

sub send_fatal_error {
    my($self, $message) = @_;
    $self->state(STATE_FAILED);
    $self->_remove_all_watchers();
    $self->on_fatal_error->($self,$message);
}

sub validate {
    my $self = shift;
    my $cb = shift;

    if ($self->state ne STATE_ACTIVE
        and
        $self->state ne STATE_RENEWING
    ) {
        $cb->(0);
        return;
    }

    my $responder = sub {
        my($body, $headers) = @_;

        my $status = $self->_response_status($headers);
        my $status_class = substr($status,0,1);
        $cb->($status_class == 2);
    };

    $self->_send_renewal_request($responder);
}


sub release {
    my $self = shift;
    my(%params) = @_;

    $self->on_success_cb($params{on_success}) || Carp::croak('on_success is required');
    $self->on_fail_cb($params{on_fail}) || Carp::croak('on_fail is required');

    if ($self->state eq STATE_NEW) {
        $self->transition(STATE_RELEASED);
        $self->_call_success_fail_callback('on_success_cb');
        return 1;
    }

    $self->transition(STATE_RELEASING);

    $self->_remove_all_watchers();

    my $responder = $self->_make_response_generator(
                        'release',
                        'recv_release_response');
    $self->_send_http_request(
        PATCH => $self->claim_location_url,
        headers => {'Content-Type' => 'application/json'},
        body => $self->json_parser->encode({ status => 'released' }),
        $responder,
    );
}

sub recv_release_response_204 {
    my $self = shift;
    $self->state(STATE_RELEASED);
    $self->_call_success_fail_callback('on_success_cb');
    1;
}

_install_sub('recv_release_response_400', __PACKAGE__->_release_failure_generator('release: bad request'));
_install_sub('recv_release_response_404', __PACKAGE__->_release_failure_generator('release: non-existent claim'));
_install_sub('recv_release_response_409', __PACKAGE__->_release_failure_generator('release: lost claim'));
_install_sub('recv_release_response_5XX', __PACKAGE__->_release_failure_generator('release: server error'));

sub _create_timer_event {
    my $self = shift;

    AnyEvent->timer(@_);
}

sub _ttl_timer_value {
    my $self = shift;
    return $self->ttl / 4;
}

sub _remove_all_watchers {
    my $self = shift;
    $self->timer_watcher(undef);
    $self->registration_timeout_watcher(undef);
}

sub _default_http_timeout_seconds { 5 }

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

