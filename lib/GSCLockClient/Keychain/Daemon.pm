package GSCLockClient::Keychain::Daemon;

use strict;
use warnings;
use GSCLockClient::Properties qw( url claims client_socket client_watcher server_watcher );

use GSCLockClient::Keychain::Daemon::Claim;

use AnyEvent;
use AnyEvent::Handle;
use JSON qw();

sub go {
    my $class = shift;

    my $self = $class->new(@_);

    $self->setup_events();
    $self->main_loop();
}

sub new {
    my $class = shift;
    my %params = @_;

    _required_params(\%params, qw(client_socket url));

    my $self = bless {}, $class;

    $self->client_socket($params{client_socket});
    $self->url($params{url});

    $self->claims({});

    return $self;
}

sub _required_params {
    my($params, @required) = @_;

    foreach my $name ( @required ) {
        unless (exists $params->{$name}) {
            die "'$name' is a required parameter to new";
        }
    }
    return 1;
}


sub setup_events {
    my $self = shift;

    my $client_watcher = $self->create_client_watcher();
    $self->client_watcher($client_watcher)
    
}

my $json_parser = JSON->new();
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

sub client_read_event {
    my $self = shift;
    my ($watcher,$message) = @_;

    my $command = delete $message->{command};
    my $result = eval {
        $self->dispatch_command( $command, $message )
    };

    $result || $self->claim_failed($message);
}

sub claim_failed {
    my($self, $message) = @_;
    $self->remove_claim($message->{resource_name});
    $self->_send_return_message($message, 0);
}

sub claim_succeeded {
    my($self, $message) = @_;
    $self->_send_return_message($message, 1);
}

sub _send_return_message {
    my($self, $message, $result) = @_;

    $message->{result} = $result ? 'success' : 'failed';
    $message->{error_message} = $@ if ($@);

    my $watcher = $self->client_watcher;
    $watcher->push_write( json => $message );
    $watcher->push_read;
}

my %allowed_command = (
    claim   => \&claim,
    release => \&release,
);

sub dispatch_command {
    my $self = shift;
    my ($command, $message) = @_;
    
    my $sub = $allowed_command{$command};
    die "Unknown command" unless $sub;

    return $self->$sub($message);
}

sub claim {
    my($self, $message) = @_;

    my($resource_name, $data) = @$message{'resource_name','data'};
    my $claim = GSCLockClient::Keychain::Daemon::Claim->new(
                    resource_name => $resource_name,
                    data => $data,
                    keychain => $self);
    if ($claim) {
        $self->add_claim($resource_name, $claim);
    }
    return $claim;
}

sub release {
    my($self, $message) = @_;

    my $resource_name = $message->{resource_name};
    my $claim = $self->remove_claim($resource_name);
    $claim || die "No claim with resource $resource_name";

    $claim->release;
}

sub add_claim {
    my($self, $resource_name, $claim) = @_;

    my $claims = $self->claims;
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
