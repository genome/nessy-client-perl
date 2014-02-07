package Nessy::Keychain::Daemon;

use strict;
use warnings;
use Nessy::Properties qw( url claims client_socket client_watcher server_watcher );

use Nessy::Keychain::Daemon::Claim;
use Nessy::Keychain::Message;

use AnyEvent;
use AnyEvent::Handle;
use JSON qw();
use Carp;

sub start {
    my $self = shift;
    my $cv = shift;

    $self->setup_events();

    # enter the event loop
    $cv ||= AnyEvent->condvar;
    $cv->recv;
}

sub new {
    my $class = shift;
    my %params = @_;

    $class->_required_params(\%params, qw(client_socket url));

    my $self = bless {}, $class;

    $self->client_socket($params{client_socket});
    $self->url($params{url});

    $self->claims({});

    return $self;
}

sub setup_events {
    my $self = shift;

    my $client_watcher = $self->create_client_watcher();
    $self->client_watcher($client_watcher)
    
}

my $json_parser = JSON->new->convert_blessed(1);
sub create_client_watcher {
    my $self = shift;

    my $w = AnyEvent::Handle->new(
                fh => $self->client_socket,
                on_error => sub { $self->client_error_event(@_); },
                on_eof => sub { $self->client_eof_event(@_); },
                json => $json_parser,
            );

    $w->push_read( json => sub {
        $self->client_read_event(@_);
    });

    $self->client_watcher($w);
}

# not a method!
sub _construct_message {
    my $message = shift;
    if (ref($message) and ref($message) eq 'HASH') {
        return Nessy::Keychain::Message->new(%$message);
    } elsif (!ref($message)) {
        return Nessy::Keychain::Message->from_json(shift);
    } else {
        Carp::croak("Don't know how to construct message from $message");
    }
}

sub client_read_event {
    my $self = shift;
    my $watcher = shift;
    my $message = _construct_message(shift);

    my $result = eval {
        $self->dispatch_command( $message )
    };

    $result || $self->claim_failed($message);
}

sub claim_failed {
    my($self, $message) = @_;
    $self->remove_claim($message->{resource_name});
    $message->result('failed');
    $self->_send_return_message($message);
}

sub claim_succeeded {
    my($self, $message) = @_;
    $message->result('succeeded');
    $self->_send_return_message($message, 1);
}

sub _send_return_message {
    my($self, $message, $result) = @_;

    $message->error_message = $@ if ($@);

    my $watcher = $self->client_watcher;
    $watcher->push_write( json => $message );
}

my %allowed_command = (
    claim   => \&claim,
    release => \&release,
);

sub dispatch_command {
    my($self, $message) = @_;
    
    my $sub = $allowed_command{$message->command};
    Carp::croak("Unknown command") unless $sub;

    return $self->$sub($message);
}

sub claim {
    my($self, $message) = @_;

    my($resource_name, $data) = @$message{'resource_name','data'};
    my $claim_class = $self->_claim_class;
    my $claim = $claim_class->new(
                    resource_name => $resource_name,
                    data => $data,
                    keychain => $self);
    if ($claim) {
        $self->add_claim($resource_name, $claim);
        $claim->start();
    }
    return $claim;
}

sub _claim_class {
    return 'Nessy::Keychain::Daemon::Claim';
}

sub release {
    my($self, $message) = @_;

    my $resource_name = $message->{resource_name};
    my $claim = $self->remove_claim($resource_name);
    $claim || Carp::croak("No claim with resource $resource_name");

    $claim->release;
}

sub add_claim {
    my($self, $resource_name, $claim) = @_;

    my $claims = $self->claims;
    if (exists $claims->{$resource_name}) {
        Carp::croak("Attempted to add claim $resource_name when it already exists");
    }
    $claims->{$resource_name} = $claim;
}

sub remove_claim {
    my($self, $resource_name) = @_;
    my $claims = $self->claims;
    return delete $claims->{$resource_name};
}

sub _respond_to_requestor {
    my($self, $message) = @_;

}
    

1;
