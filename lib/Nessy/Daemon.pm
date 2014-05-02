package Nessy::Daemon;

use strict;
use warnings;
use Nessy::Properties qw( url claims client_socket client_watcher server_watcher ppid event_loop_cv api_version _serial_lookup);

use Nessy::Daemon::ClaimFactory;
use Nessy::Client::Message;

use AnyEvent;
use AnyEvent::Handle;
use JSON qw();
use Carp;
use Scalar::Util qw();
use Getopt::Long;
use File::Basename;
use Fcntl;
use List::Util qw(max);


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
        if (defined($claim)) {
            $claim->terminate;
        }
    }
}

sub new {
    my $class = shift;
    my %params = @_;

    my $self = $class->_verify_params(\%params, qw(client_socket url api_version));
    bless $self, $class;

    $self->ppid(getppid);
    $self->_serial_lookup({});
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
        _log_error("client_error_event: $msg");
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
    shift;
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

    $self->_save_message_serial($message);

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

sub _save_message_serial {
    my ($self, $message) = @_;

    $self->_serial_lookup->{$message->command}->{$message->resource_name} = $message->serial;
}

sub _get_message_serial {
    my ($self, $command, $resource_name) = @_;

    return $self->_serial_lookup->{$command}->{$resource_name};
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
    validate => 'validate',
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

    my %params = (
        resource => $resource_name,

        on_active => sub { $self->_claim_activated($resource_name) },
        on_withdrawn => sub { $self->_claim_timed_out($resource_name) },
        on_fatal_error => sub { $self->_claim_errored($resource_name) },
        on_released => sub { $self->_claim_released($resource_name) },

        submit_url => $self->submit_url,

        activate_seconds => 60,
        renew_seconds => max(1, $args->{ttl} / 4),
        retry_seconds => 3,

        max_activate_backoff_factor => 60,  # 15 minutes max
        max_retry_backoff_factor => 60,     #  5 minutes max
    );

    my $claim = Nessy::Daemon::ClaimFactory->new(
        %params,
        %$args,
    );


    if ($claim) {
        $self->add_claim($claim);
        $claim->start;
    }
    return $claim;
}

sub submit_url {
    my $self = shift;

    return sprintf('%s/%s/claims/', $self->url, $self->api_version);
}

sub _claim_activated {
    my ($self, $resource_name) = @_;

    my $serial = $self->_get_message_serial('claim', $resource_name);
    my $message = Nessy::Client::Message->new(
        command => 'claim',
        resource_name => $resource_name,
        serial => $serial,
    );

    $message->succeed;

    $self->_send_return_message($message);
}

sub _claim_errored {
    my ($self, $resource_name) = @_;

    my $claim = $self->lookup_claim($resource_name);
    $self->remove_claim($claim);

    $self->fatal_error("Fatal error from claim: '$resource_name'");
}

sub _claim_released {
    my ($self, $resource_name) = @_;

    my $claim = $self->lookup_claim($resource_name);
    $self->remove_claim($claim);

    my $serial = $self->_get_message_serial('release', $resource_name);
    my $message = Nessy::Client::Message->new(
        command => 'release',
        resource_name => $resource_name,
        serial => $serial,
    );

    $message->succeed;

    $self->_send_return_message($message);
}

sub _claim_timed_out {
    my ($self, $resource_name) = @_;

    my $claim = $self->lookup_claim($resource_name);
    $self->remove_claim($claim);

    my $serial = $self->_get_message_serial('claim', $resource_name);
    my $message = Nessy::Client::Message->new(
        command => 'claim',
        resource_name => $resource_name,
        serial => $serial,
    );

    $message->error_message("Claim timed out for resource: '$resource_name'");
    $message->fail;

    $self->_send_return_message($message);
}


sub _on_fatal_error {
    my($self, $fatal_claim, $message) = @_;

    $self->remove_claim($fatal_claim);
    $message = sprintf("claimed resource %s: %s", $fatal_claim->resource_name, $message);
    $self->fatal_error($message);
}

sub release {
    my($self, $message) = @_;

    $self->_save_message_serial($message);

    my $resource_name = $message->resource_name;
    my $claim = $self->lookup_claim($resource_name);
    # XXX Should this be done inside the lookup function?
    $claim || Carp::croak("No claim with resource $resource_name");

    $claim->release;

    1;
}

sub validate {
    my($self, $message) = @_;

    my $resource_name = $message->resource_name;
    my $claim = $self->lookup_claim($resource_name);

    my $responder = sub {
        my $is_active = shift;
        if ($is_active) {
            $message->succeed;
        } else {
            $message->fail;
        }

        $self->_send_return_message($message);
    };

    $claim->validate($responder);

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

    unless ($ENV{NESSY_TEST}) {
        _log_error("Fatal error: $message");
    }

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
    my($error_message) = @_;
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

=pod

=head1 NAME

Nessy::Daemon - Process to manage Claims for the main program

=head1 DESCRIPTION

The Dameon process is started by L<Nessy::Client> to manage claims on behalf of
the main program. Since Nessy claims must be refreshed periocically, the Daemon
process allows this to happen even if the main program is not event based.  The
Client and Daemon communicate over a file descriptior by sending L<Nessy::Client::Message>
objects serialized with the JSON module.

=head1 CONSTRUCTOR

  my $daemon = Nessy::Daemon->new(
                    url => $server_url,
                    client_socket => $socket_object,
                    api_version => $version );
  $daemon->run();

Creates a new Nessy::Daemon instance.  C<url> is the top-level URL of the
Nessy server.  C<api_version> is the dialect to use when talking to the
Nessy server.  C<client_socket> is a L<IO::Socket> instance to communicate
over.

The C<run> method does a fork/exec to run the Nessy::Daemon module from the
command line, while keeping the communication socket open.  If the Daemon
detects the socket is closed, it will exit.

=head1 Commands

The Client controls the Daemon by sending serialized L<Nessy::Client::Message>
objects through the open socket.  Commands are processed initially by C<dispatch_command()>.
The following commands are recognized:

=over 4

=item claim()

Create a new L<Nessy::Daemon::Claim> object and call C<start()> on it.  The Message
args may contain these key/value pairs:

=over 2

=item user_data

=item ttl

=item timeout

=back

=item release()

Release the resource named in the Message.

=item validate()

Call C<validate()> on the Claim named in the Message.

=item ping()

The Daemon immediately responds with a successful response.

=item shutdown

Shuts down the Daemon by first releasing all currently held Claims and
then exiting.  This command is implemented by the C<shutdown_cmd()> method.

=back

L<Nessy::Claim>, L<Nessy::Daemon::Claim>

=head1 LICENCE AND COPYRIGHT

Copyright (C) 2014 Washington University in St. Louis, MO.

This sofware is licensed under the same terms as Perl itself.
See the LICENSE file in this distribution.

=cut

