package Nessy::Daemon::Claim;

use strict;
use warnings;

use Nessy::Properties qw(
            resource_name user_data state url claim_location_url timer_watcher ttl api_version
            on_success_cb on_fail_cb on_fatal_error);

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


my $json_parser = JSON->new();
sub new {
    my($class, %params) = @_;

    my $self = $class->_verify_params(\%params, qw(url resource_name ttl on_fatal_error api_version));
    bless $self, $class;
    $self->state(STATE_NEW);
    return $self;
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
        $self->_remove_all_watchers();
        $self->state(STATE_FAILED);
        $self->_call_success_fail_callback('on_fail_cb', $error);
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

    $self->_send_http_request(
        POST => $self->url . '/' . $self->api_version . '/claims/',
        headers => {'Content-Type' => 'application/json'},
        body => $json_parser->encode($request_body),
        $responder,
    );
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
        body => $json_parser->encode({ status => 'active' }),
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
    my $ttl = $self->ttl;
    $self->_send_http_request(
        PATCH => $self->claim_location_url,
        headers => {'Content-Type' => 'application/json'},
        timeout => ($self->_ttl_timer_value / 2),
        body => $json_parser->encode({ ttl => $ttl }),
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
        body => $json_parser->encode({ status => 'released' }),
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
}

sub _default_http_timeout_seconds { 5 }

1;
