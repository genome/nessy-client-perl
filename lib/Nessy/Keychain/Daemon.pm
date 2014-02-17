package Nessy::Keychain::Daemon;

use strict;
use warnings;
use Nessy::Properties qw( url claims client_socket client_watcher server_watcher ppid event_loop_cv default_ttl api_version);

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
    $self->event_loop_cv($cv);
    $cv->recv;
}

sub shutdown {
    my $self = shift;

    if (my $w = $self->client_watcher) {
        $self->client_watcher( undef );
        $w->destroy;
    }

    $self->client_socket( undef );
    $self->_release_all_claims_in_shutdown;
}

sub _release_all_claims_in_shutdown {
    my $self = shift;
    foreach my $claim ( $self->all_claims ) {
        $claim->release(
                on_success => sub { 1 },
                on_fail => sub {
                        my ($claim, $error) = @_;
                        $self->_log_error($error);
                },
            );
    }
}

sub new {
    my $class = shift;
    my %params = @_;

    my $self = $class->_verify_params(\%params, qw(client_socket url default_ttl api_version));
    bless $self, $class;

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
    if ($is_fatal) {
        $self->fatal_error($msg);
    } else {
        $self->_log_error("client_error_event: $msg");
    }
}

sub client_eof_event {
    my($self, $w) = @_;
    $self->_exit_cleanly(0);
}

sub _exit_cleanly {
    my($self, $code) = @_;
    $self->event_loop_cv->send($code);
    $self->_exit($code);
}

sub _exit {
    exit shift;
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
            no warnings 'uninitialized';
            $message->error_message(sprintf("command %s returned false: $result", $message->command));
        }
        $self->_send_return_message($message);
    }
    return $result
}

sub claim_failed {
    my($self, $claim, $message, $error_message) = @_;

    $message->error_message($error_message);
    $self->remove_claim($claim);
    $message->fail;
    $self->_send_return_message($message);
}

sub claim_succeeded {
    my($self, $claim, $message) = @_;

    $message->succeed();
    $self->_send_return_message($message);
}

sub release_failed {
    my($self, $claim, $message, $error_message) = @_;

    $message->error_message($error_message);
    $message->fail;
    $self->_send_return_message($message);
}

sub release_succeeded {
    my($self, $claim, $message) = @_;

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
    ping    => \&ping,
);

sub dispatch_command {
    my($self, $message) = @_;
    
    my $sub = $allowed_command{$message->command};
    Carp::croak("Unknown command: ".$message->command) unless $sub;

    return $self->$sub($message);
}

sub ping {
    my($self, $message) = @_;
print "Got a ping!\n";
    $message->succeed;
    $self->_send_return_message($message);
    1;
}

sub claim {
    my($self, $message) = @_;

    my($resource_name, $data) = map { $message->$_ } qw(resource_name data);
    my $claim_class = $self->_claim_class;

    my $self_copy = $self;
    Scalar::Util::weaken($self_copy);
    my $claim = $claim_class->new(
                    resource_name => $resource_name,
                    data => $data,
                    ttl => $self->default_ttl,
                    api_version => $self->api_version,
                    on_fatal_error => sub { $self_copy->fatal_error($_[1]) },
                );
    if ($claim) {
        $self->add_claim($claim);
        $claim->start(
            on_success => sub { $self->claim_succeeded($claim, $message) },
            on_fail => sub {
                            my(undef, $error_message) = @_;
                            $self->claim_failed($claim, $message, $error_message);
                        },
        );
    }
    return $claim;
}

sub _claim_class {
    return 'Nessy::Keychain::Daemon::Claim';
}

sub release {
    my($self, $message) = @_;

    my $resource_name = $message->{resource_name};
    my $claim = $self->lookup_claim($resource_name);
    $claim || Carp::croak("No claim with resource $resource_name");
    $self->remove_claim($claim);

    $claim->release(
            on_success => sub { $self->release_succeeded($claim, $message) },
            on_fail => sub {
                            my(undef, $error_message) = @_;
                            $self->claim_failed($claim, $message, $error_message);
                        },
        );
}

sub add_claim {
    my($self, $claim) = @_;

    my $resource_name = $claim->resource_name;
    my $claims = $self->claims;
    if (exists $claims->{$resource_name}) {
        Carp::croak("Attempted to add claim $resource_name when it already exists");
    }
    $claims->{$resource_name} = $claim;
}

sub remove_claim {
    my($self, $claim) = @_;
    my $resource_name = $claim->resource_name;
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

    $self->_log_error("Fatal error: $message");
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

sub _log_error {
    my($self, $error_message) = @_;
    print STDERR $error_message,"\n";
    eval {
        require AnyEvent::Debug;
        print STDERR AnyEvent::Debug::backtrace(2);
    };
}

sub DESTROY {
    my $self = shift;
    $self->shutdown;
}
1;
