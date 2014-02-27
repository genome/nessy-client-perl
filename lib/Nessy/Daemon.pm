package Nessy::Daemon;

use strict;
use warnings;
use Nessy::Properties qw( url claims client_socket client_watcher server_watcher ppid event_loop_cv api_version);

use Nessy::Daemon::Claim;
use Nessy::Client::Message;

use AnyEvent;
use AnyEvent::Handle;
use JSON qw();
use Carp;
use Scalar::Util qw();
use Getopt::Long;
use File::Basename;
use Fcntl;

sub start {
    my $self = shift;
    my $cv = shift;

    $self->setup_events();

    # enter the event loop
    $cv ||= AnyEvent->condvar;
    $self->event_loop_cv($cv);
    $cv->recv;
}

sub run {
    my $self = shift;

    # clear the close-on-exec flag
    my $sock_flags = fcntl($self->client_socket, F_GETFD, 0) || die "fcntl F_GETFD: $!";
    fcntl($self->client_socket, F_SETFD, $sock_flags & ~FD_CLOEXEC) || die "fcntl F_SETFD: $!";

    my $client_socket_fd = fileno($self->client_socket);

    my $inc = File::Basename::dirname(__FILE__) . '/..';
    my @cover; @cover = qw(-MDevel::Cover) if ($INC{'Devel/Cover.pm'});
    exec($^X,
        '-I', $inc,
        @cover,
        __FILE__,
        '--fd', $client_socket_fd,
        map { ("--$_" , $self->$_) } qw(url api_version));
    die "daemon exec failed: $!";
}

sub _run {
    my($url, $client_socket_fd, $default_ttl, $api_version);
    my $options = GetOptions(
                    'url=s'         => \$url,
                    'fd=i'          => \$client_socket_fd,
                    'default_ttl=i' => \$default_ttl,
                    'api_version=s' => \$api_version);
    my $client_socket;
    open($client_socket, '>>&=', $client_socket_fd) || die "Can't create filehandle for fd $client_socket_fd: $!";

    my $self = __PACKAGE__->new(url => $url,
                                client_socket => $client_socket,
                                default_ttl => $default_ttl,
                                api_version => $api_version);
    $self->start();
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

    my $self = $class->_verify_params(\%params, qw(client_socket url api_version));
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
        return Nessy::Client::Message->new(%$message);
    } elsif (!ref($message)) {
        return Nessy::Client::Message->from_json(shift);
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
        $message->fail;
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

    my $watcher = $self->client_watcher;
    return unless $watcher;
    $watcher->push_write( json => $message );
    return $message;
}

my %allowed_command = (
    claim   => 'claim',
    release => 'release',
    ping    => 'ping',
    shutdown => 'shutdown_cmd',
);

sub dispatch_command {
    my($self, $message) = @_;
    
    my $sub = $allowed_command{$message->command};
    Carp::croak("Unknown command: ".$message->command) unless $sub;

    return $self->$sub($message);
}

sub ping {
    my($self, $message) = @_;
    $message->succeed;
    $self->_send_return_message($message);
    1;
}

sub shutdown_cmd {
    my($self, $message) = @_;
    $self->_release_all_claims_in_shutdown;

    $message->succeed;
    $self->_send_return_message($message);

    $self->client_watcher->on_drain(sub {
        $self->_exit_cleanly(0);
    });
    1;
}


sub claim {
    my($self, $message) = @_;

    my($resource_name, $args) = map { $message->$_ } qw(resource_name args);
    my $claim_class = $self->_claim_class;

    my $self_copy = $self;
    Scalar::Util::weaken($self_copy);

    my $claim = $claim_class->new(
                    resource_name => $resource_name,
                    user_data => $args->{user_data},
                    url => $self->url,
                    ttl => $args->{ttl},
                    api_version => $self->api_version,
                    on_fatal_error => sub { $self_copy->_on_fatal_error(@_) },
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

sub _on_fatal_error {
    my($self, $fatal_claim, $message) = @_;

    $self->remove_claim($fatal_claim);
    $message = sprintf("claimed resource %s: %s", $fatal_claim->resource_name, $message);
    $self->fatal_error($message);
}

sub _claim_class {
    return 'Nessy::Daemon::Claim';
}

sub release {
    my($self, $message) = @_;

    my $resource_name = $message->resource_name;
    my $claim = $self->lookup_claim($resource_name);
    $claim || Carp::croak("No claim with resource $resource_name");
    $self->remove_claim($claim);

    $claim->release(
            on_success => sub { $self->release_succeeded($claim, $message) },
            on_fail => sub {
                            my(undef, $error_message) = @_;
                            $self->release_failed($claim, $message, $error_message);
                        },
        );
    1;
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

sub fatal_error {
    my($self, $message) = @_;

    $self->_log_error("Fatal error: $message");
    $self->_try_kill_parent('TERM');
    sleep($self->fatal_error_delay_time);
    $self->_exit_if_parent_dead(1);
    $self->_try_kill_parent($ENV{NESSY_TEST} ? 'TERM' : 'KILL');
    exit(1);
}

sub fatal_error_delay_time { $ENV{NESSY_TEST} ? 1 : 10 } # seconds

sub _try_kill_parent {
    my($self, $signal) = @_;

    kill($signal, $self->ppid);
}

sub _exit_if_parent_dead {
    my($self, $exit_code) = @_;
    exit($exit_code) unless (kill(0, $self->ppid));
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

unless (caller) {
    _run();
}
1;
