package Nessy::Keychain::Daemon;

use strict;
use warnings;
use Nessy::Properties qw( url claims client_socket client_watcher server_watcher ppid);

use Nessy::Keychain::Daemon::Claim;
use Nessy::Keychain::Message;

use AnyEvent;
use AnyEvent::Handle;
use JSON qw();
use Carp;
use Scalar::Util qw();

sub start {
    my $self = shift;
    my $cv = shift;

    $self->setup_events();

    # enter the event loop
    $cv ||= AnyEvent->condvar;
    $cv->recv;
}

sub shutdown {
    my $self = shift;

    if (my $w = $self->client_watcher) {
        $self->client_watcher( undef );
        $w->destroy;
    }

    $self->client_socket( undef );

    $_->release for $self->all_claims;
}

sub new {
    my $class = shift;
    my %params = @_;

    my $self = bless {}, $class;
    $self->_required_params(\%params, qw(client_socket url));

    $self->ppid(getppid);

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

    Scalar::Util::weaken( $self );
    my $w = AnyEvent::Handle->new(
                fh => $self->client_socket,
                on_error    => sub { $self->client_error_event(@_) },
                on_eof      => sub { $self->client_eof_event(@_) },
                on_read     => sub { $self->on_read_handler(@_) },
                #oob_inline => 0,
                json => $json_parser,
            );
    return $w;
}

sub on_read_handler {
    my($self, $w) = @_;
    $w->unshift_read( json => sub { $self->client_read_event(@_); });
}

sub client_error_event {
    my($self, $w, $is_fatal, $msg) = @_;
    print "*** Error.  is_fatal: $is_fatal: $msg\n";
}

sub client_eof_event {
    my($self, $w) = @_;
    print "*** at EOF\n";

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

    unless ($result) {
        if ($@) {
            $message->error_message(sprintf('command %s exception: %s', $message->command, $@));
        } else {
            $message->error_message(sprintf("command %s returned false: $result", $message->command));
        }
        $message->fail;
        $self->_send_return_message($message);
    }
    return $result
}

sub claim_failed {
    my($self, $resource_name, $error_message) = @_;
    my $message = Nessy::Keychain::Message->new(
                    resource_name => $resource_name,
                    command => 'claim',
                    error_message => $error_message);
    $message->fail;
    $self->remove_claim($resource_name);
    $self->_send_return_message($message);
}

sub claim_succeeded {
    my($self, $resource_name) = @_;

    my $message = Nessy::Keychain::Message->new(
                    resource_name => $resource_name,
                    command => 'claim');
    $message->succeed();
    $self->_send_return_message($message);
}

sub release_failed {
    my($self, $resource_name, $error_message) = @_;

    my $message = Nessy::Keychain::Message->new(
                    resource_name => $resource_name,
                    command => 'release',
                    error_message => $error_message);
    $message->fail;
    $self->_send_return_message($message);
}

sub release_succeeded {
    my($self, $resource_name) = @_;

    my $message = Nessy::Keychain::Message->new(
                    resource_name => $resource_name,
                    command => 'release');
    $message->succeed;
    $self->_send_return_message($message);
}

sub _send_return_message {
    my($self, $message) = @_;

    $message->error_message($@) if ($@);

    my $watcher = $self->client_watcher;
    return unless $watcher;
    $watcher->push_write( json => $message );
    return $message;
}

my %allowed_command = (
    claim   => \&claim,
    release => \&release,
);

sub dispatch_command {
    my($self, $message) = @_;
    
    my $sub = $allowed_command{$message->command};
    Carp::croak("Unknown command: ".$message->command) unless $sub;

    return $self->$sub($message);
}

sub claim {
    my($self, $message) = @_;

    my($resource_name, $data) = map { $message->$_ } qw(resource_name data);
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

sub lookup_claim {
    my ($self, $resource_name) = @_;
    my $claims = $self->claims;
    return $claims->{$resource_name};
}

sub all_claims {
    my $self = shift;
    my $claims = $self->claims;
    values %$claims;
}

sub _respond_to_requestor {
    my($self, $message) = @_;

}

sub fatal_error {
    my($self, $message) = @_;

    Carp::carp("Fatal error: $message");
    $self->_try_kill_parent('TERM');
    sleep($self->fatal_error_delay_time);
    $self->_exit_if_parent_dead(1);
    $self->_try_kill_parent('KILL');
    exit(1);
}

sub fatal_error_delay_time { 10 } # seconds

sub _try_kill_parent {
    my($self, $signal) = @_;

    kill($signal, $self->ppid);
}

sub _exit_if_parent_dead {
    my($self, $exit_code) = @_;
    exit($exit_code) if (kill(0, $self->ppid));
}

sub DESTROY {
    my $self = shift;
    $self->shutdown;
}
1;
