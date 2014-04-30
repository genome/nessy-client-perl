package Nessy::Daemon::CommandInterface;

use strict;
use warnings FATAL => 'all';

use Nessy::Properties qw(
    event_generator
    resource
    submit_url
    ttl
    update_url
    user_data

    on_active
    on_withdrawn
    on_fatal_error
    on_released

    activate_seconds
    renew_seconds
    retry_seconds

    max_activate_backoff_factor
    max_retry_backoff_factor

    timeout_seconds

    _current_activate_backoff_factor
    _current_retry_backoff_factor
    _current_timer_watcher
    _http_response_watcher
    _timeout_watcher
);

use AnyEvent;
use AnyEvent::HTTP;
use JSON;

use List::Util qw(min);

sub new {
    my $class = shift;
    my %params = @_;

    my $self = bless $class->_verify_params(\%params, qw(
        event_generator
        resource
        submit_url
        ttl

        on_active
        on_withdrawn
        on_fatal_error
        on_released

        activate_seconds
        renew_seconds
        retry_seconds

        max_activate_backoff_factor
        max_retry_backoff_factor
    )), $class;

    $self->_current_activate_backoff_factor(1);
    $self->_current_retry_backoff_factor(1);

    return $self;
}

sub is_active {
    my $self = shift;

    # XXX Implement this with a blocking http (retry) call to the update_url
    1;
}


sub abandon_last_request {
    my $self = shift;
    $self->_http_response_watcher(undef);

    1;
}


sub abort_claim {
    my $self = shift;

    $self->_patch_status('aborted');
}


sub activate_claim {
    my $self = shift;

    $self->_patch_status('active');
}


sub create_activate_timer {
    my $self = shift;

    my $backoff = $self->_get_activate_backoff;
    my $backed_off_seconds = $backoff * $self->activate_seconds;

    $self->_create_timer($backed_off_seconds);
}


sub _get_activate_backoff {
    my $self = shift;

    my $backoff = $self->_current_activate_backoff_factor;
    $self->_current_activate_backoff_factor(
        min($backoff + 1, $self->max_activate_backoff_factor));
}


sub create_retry_timer {
    my $self = shift;

    my $backoff = $self->_get_retry_backoff;
    my $backed_off_seconds = $backoff * $self->retry_seconds;

    $self->_create_timer($backed_off_seconds);
}


sub _get_retry_backoff {
    my $self = shift;

    my $backoff = $self->_current_retry_backoff_factor;
    $self->_current_retry_backoff_factor(
        min($backoff + 1, $self->max_retry_backoff_factor));
}


sub create_renew_timer {
    my $self = shift;

    $self->_create_timer($self->renew_seconds);
}


sub _create_timer {
    my ($self, $seconds) = @_;

    $self->_current_timer_watcher(AnyEvent->timer(
        after => $seconds,
        cb => sub {
            $self->event_generator->timer_callback($self)
        },
    ));

    1;
}

sub create_timeout {
    my $self = shift;

    if ($self->timeout_seconds) {
        $self->_timeout_watcher(AnyEvent->timer(
            after => $self->timeout_seconds,
            cb => sub {
                $self->event_generator->timeout_callback($self)
            },
        ));
    }

    1;
}


sub delete_timer {
    my $self = shift;
    $self->_current_timer_watcher(undef);

    1;
}


sub delete_timeout {
    my $self = shift;
    $self->_timeout_watcher(undef);

    1;
}


sub notify_claim_withdrawn {
    my $self = shift;

    $self->on_withdrawn->(@_);

    1;
}


sub notify_lock_active {
    my $self = shift;

    $self->on_active->(@_);

    1;
}


sub notify_lock_released {
    my $self = shift;

    $self->on_released->(@_);

    1;
}


sub register_claim {
    my $self = shift;

    $self->_http('POST', $self->submit_url, $self->_register_body);

}

sub _register_body {
    my $self = shift;

    return $self->json_parser->encode(
        {
            'resource' => $self->resource,
            'ttl' => $self->ttl,
            'user_data' => $self->user_data,
        }
    );
}


sub release_claim {
    my $self = shift;

    $self->_patch_status('released');
}


sub renew_claim {
    my $self = shift;

    $self->_patch($self->json_parser->encode({ttl => $self->ttl}));
}


sub reset_retry_backoff {
    my $self = shift;

    $self->_current_retry_backoff_factor(1);

    1;
}


sub terminate_client {
    my $self = shift;

    $self->on_fatal_error->(@_);

    1;
}


sub withdraw_claim {
    my $self = shift;

    $self->_patch_status('withdrawn');
}


sub _patch_status {
    my ($self, $status) = @_;

    $self->_patch($self->_status_body($status));
}

sub _patch {
    my ($self, $body) = @_;

    $self->_http('PATCH', $self->update_url, $body);
}

sub _http {
    my ($self, $method, $url, $body) = @_;

    $self->_http_response_watcher(
        AnyEvent::HTTP::http_request(
            $method => $url,
            headers => $self->_standard_headers,
            body => $body,
            cb => sub {
                $self->event_generator->http_response_callback($self, @_);
            },
        )
    );

    1;
}


sub _status_body {
    my ($self, $status) = @_;
    return $self->json_parser->encode({status => $status});
}

sub _standard_headers {
    return {'Content-Type' => 'application/json',
        'Accept' => 'application/json'};
}

my $json_parser;
sub json_parser {
    $json_parser ||= JSON->new();
}


1;
