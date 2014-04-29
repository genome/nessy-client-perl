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

    _current_timer
    _http_response_watcher
);

use AnyEvent;
use AnyEvent::HTTP;
use JSON;


sub new {
    my $class = shift;
    my %params = @_;

    return bless $class->_verify_params(\%params,
        qw(event_generator resource submit_url ttl)), $class;
}


sub abort_claim {
    my $self = shift;

    $self->_patch_status('aborted', 'abort_callback');
}


sub activate_claim {
    my $self = shift;

    $self->_patch_status('active', 'activate_callback');
}


sub create_timer {
    my $self = shift;
    my %params = @_;
    my $seconds = $params{seconds};

    $self->_current_timer(AnyEvent->timer(
        after => $seconds,
        cb => sub {
            $self->event_generator->timer_callback()
        },
    ));

    1;
}


sub delete_timer {
    my $self = shift;
    $self->_current_timer(undef);

    1;
}


sub ignore_last_command {
    my $self = shift;
    $self->_http_response_watcher(undef);
}


sub notify_claim_withdrawn {
    my $self = shift;
}


sub notify_lock_active {
    my $self = shift;
}


sub notify_lock_released {
    my $self = shift;
}


sub register_claim {
    my $self = shift;

    $self->_http_response_watcher(
        AnyEvent::HTTP::http_request(
            POST => $self->submit_url,
            body => $self->_register_body,
            headers => $self->_standard_headers,
            cb => sub {
                $self->event_generator->registration_callback(@_);
            },
        )
    );
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

    $self->_patch_status('released', 'release_callback');
}


sub renew_claim {
    my $self = shift;

    $self->_patch('renew_callback', $self->json_parser->encode({
                ttl => $self->ttl}));
}


sub terminate_client {
    my $self = shift;
}


sub withdraw_claim {
    my $self = shift;

    $self->_patch_status('withdrawn', 'withdraw_callback');
}


sub _patch_status {
    my ($self, $status, $callback_name) = @_;

    $self->_patch($callback_name, $self->_status_body($status));
}

sub _patch {
    my ($self, $callback_name, $body) = @_;

    $self->_http_response_watcher(
        AnyEvent::HTTP::http_request(
            PATCH => $self->update_url,
            headers => $self->_standard_headers,
            body => $body,
            cb => sub {
                $self->event_generator->$callback_name(@_);
            },
        )
    );

    return 1;
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
