package Nessy::Daemon::CommandInterface;

use strict;
use warnings FATAL => 'all';

use Nessy::Properties qw(event_generator resource submit_url ttl user_data
    _current_timer _http_response_watcher);

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

    $self->_patch_status('aborted');
}


sub activate_claim {
    my $self = shift;

    $self->_patch_status('active');
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

    $self->_patch_status('released');
}


sub renew_claim {
    my $self = shift;
}


sub terminate_client {
    my $self = shift;
}


sub withdraw_claim {
    my $self = shift;

    $self->_patch_status('withdrawn');
}


sub _patch_status {
    my ($self, $status) = @_;

    return 1;
}


my $json_parser;
sub json_parser {
    $json_parser ||= JSON->new();
}


1;
