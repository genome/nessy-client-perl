package Nessy::Client;

use strict;
use warnings;

our $VERSION = '0.010';

use Nessy::Properties qw(pid socket socket_watcher serial_responder_registry api_version default_ttl default_timeout);

use Nessy::Claim;
use Nessy::Daemon;

use Carp;
use Socket;
use IO::Socket;
use JSON qw();
use AnyEvent;
use AnyEvent::Handle;
use Scalar::Util;

my $MESSAGE_SERIAL = 1;

use constant PARENT_PROCESS_SOCKET => 0;  # index into $params{socketpair}
use constant CHILD_PROCESS_SOCKET => 1;

# The client process that acts as an intermediary between the client code
# and the lock server 

sub new {
    my($class, %params) = @_;

    $class->_verify_constructor_params(\%params);
    my $self = bless {}, $class;
    $self->constructor_params(\%params);

    $self->_fork_and_run_daemon();
    return $self;
}

sub _fork_and_run_daemon {
    my $self = shift;

    my @sockets = $self->_make_socket_pair_for_daemon_comms();

    my $pid = $self->_fork();
    if ($pid) {
        $self->pid($pid);
        $self->_parent_process_setup(@sockets);
        return $pid;

    } elsif (defined $pid) {
        $self->_run_child_process(@sockets);
        exit;
    } else {
        Carp::croak("Can't fork: $!");
    }
}

sub constructor_params {
    my $self = shift;
    if (@_) {
        $self->{constructor_params} = shift;
    }
    return $self->{constructor_params};
}

sub _verify_constructor_params {
    my($class, $params) = @_;

    $params->{api_version} ||= $class->_default_api_version;
    $params->{url} || Carp::croak('url is a required param');
    $params->{default_ttl} ||= $class->_default_ttl;
    $params->{default_timeout} ||= $class->_default_timeout;

    return $params;
}

sub _make_socket_pair_for_daemon_comms {
    my($socket1, $socket2) = IO::Socket->socketpair(AF_UNIX, SOCK_STREAM, PF_UNSPEC);
    $_->autoflush(1) foreach ($socket1, $socket2);

    return ($socket1, $socket2);
}

sub _parent_process_setup {
    my($self, @sockets) = @_;

    my $params = $self->constructor_params();

    $self->api_version($params->{api_version});
    $self->default_ttl($params->{default_ttl});
    $self->default_timeout($params->{default_timeout});
    $self->serial_responder_registry({});

    my $watcher = $self->_create_socket_watcher($sockets[PARENT_PROCESS_SOCKET]);
    $self->socket_watcher($watcher);

    $self->_close_unused_socket($sockets[CHILD_PROCESS_SOCKET]);
}

# After forking, the parent closes the child's socket, and the child closes
# the parent's socket
sub _close_unused_socket {
    my($self, $sock) = @_;
    $sock->close();
}

sub _run_child_process {
    my($self, @sockets) = @_;

    my $params = $self->constructor_params();

    eval {
        $self->_close_unused_socket($sockets[PARENT_PROCESS_SOCKET]);
        my $daemon_class = $self->_daemon_class_name;
        my $daemon = $daemon_class->new(
                            url => $params->{url},
                            client_socket => $sockets[CHILD_PROCESS_SOCKET],
                            api_version => $params->{api_version});
        $daemon->run();
    };
    Carp::croak($@) if $@;
}

sub _default_ttl { 60 } # seconds
sub _default_timeout { undef } # seconds or undef means wait as long as it takes
sub _default_api_version { 'v1' }

sub _daemon_class_name { 'Nessy::Daemon' }

sub _claim_class_name { 'Nessy::Claim' }

sub _fork { fork }

sub shutdown {
    my($self, $timeout, $cb) = @_;

    $timeout ||= 0;
    my $is_blocking = !$cb;
    $cb ||= AnyEvent->condvar;

    my $report_response_succeeded = sub {
        my $response = shift;
        $cb->( $response->is_succeeded );
    };

    my $result = $self->_send_command_with_callback(
        $report_response_succeeded,
        command => 'shutdown',
        resource_name => ''
    );

    if ($is_blocking) {
        my $shutdown_sub = $self->_shutdown_timeout_sub;
        return $cb->recv();
    }
    return;
}

sub _shutdown_timeout_sub {
    return sub {};
}

sub claim {
    my($self, $resource_name, %params) = @_;

    $resource_name || Carp::croak('resource_name is a required param');

    my($user_data, $cb, $ttl, $timeout) = delete @params{'user_data','cb','ttl','timeout'};

    my $is_blocking = !$cb;
    $cb ||= AnyEvent->condvar;

    my(undef, $filename, $line) = caller;
    my $caller_location = "$filename:$line";

    my $report_response = sub {
        my $response = shift;
        my $claim;
        if ($response->is_succeeded) {
            my $claim_class = $self->_claim_class_name;
            my $on_release = $self->_make_on_release_closure($resource_name, $caller_location);
            my $on_validate = $self->_make_on_validate_closure($resource_name, $caller_location);
            $claim = $claim_class->new(
                    resource_name => $resource_name,
                    on_release => $on_release,
                    on_validate => $on_validate,
                );
        } else {
            warn("claim $resource_name at $caller_location failed: ".$response->error_message);
        }
        $cb->($claim);
    };

    $ttl ||= $self->default_ttl;
    $timeout ||= $self->default_timeout;
    my $result = $self->_send_command_with_callback(
        $report_response,
        command => 'claim',
        resource_name => $resource_name,
        args => {
            user_data => $user_data,
            ttl => $ttl,
            timeout_seconds => $timeout,
            %params,
        },
    );

    if ($is_blocking) {
        return $cb->recv;
    }
    return;
}

sub _make_on_release_closure {
    my($self, $resource_name, $caller_location) = @_;

    return sub {
        my $provided_cb = shift;

        if ($provided_cb) {
            # non-blocking.  Wrap the provided callback so we can give a useful
            # warning when it ultimately completes
            my $cb = sub {
                my $result = shift;
                $provided_cb->($result);
                unless ($result) {
                    Carp::carp "release $resource_name failed. Claim originated at $caller_location";
                }
            };
            $self->_release($resource_name, $cb);

        } else {
            my $rv = $self->_release($resource_name);
            unless ($rv) {
                Carp::carp "release $resource_name failed. Claim originated at $caller_location";
            }
            return $rv;
        }
    };
}

sub _make_on_validate_closure {
    my($self, $resource_name, $caller_location) = @_;

    return sub {
        my $provided_cb = shift;

        if ($provided_cb) {
            $self->_validate_claim($resource_name, $provided_cb);
        } else {
            $self->_validate_claim($resource_name);
        }
    }
}

sub _release {
    my($self, $resource_name, $cb) = @_;

    my $is_blocking = !$cb;
    $cb ||= AnyEvent->condvar;

    my $report_response_succeeded = sub {
        my $response = shift;
        $cb->( $response->is_succeeded );
    };

    my $result = $self->_send_command_with_callback(
        $report_response_succeeded,
        command => 'release',
        resource_name => $resource_name,
    );

    if ($is_blocking) {
        return $cb->recv;
    }
    return;
}

sub _validate_claim {
    my($self, $resource_name, $cb) = @_;

    my $is_blocking = !$cb;
    $cb ||= AnyEvent->condvar;

    my $report_response_succeeded = sub {
        my $response = shift;
        $cb->( $response->is_succeeded );
    };

    my $result = $self->_send_command_with_callback(
        $report_response_succeeded,
        command => 'validate',
        resource_name => $resource_name,
    );

    if ($is_blocking) {
        return $cb->recv;
    }
    return;
}

sub ping {
    my $self = shift;
    my $cb = shift;

    my $is_blocking = ! $cb;
    $cb ||= AnyEvent->condvar;

    my $report_response_succeeded = sub {
        my $response = shift;
        $cb->( $response->is_succeeded );
    };

    $self->_send_command_with_callback(
                $report_response_succeeded,
                resource_name => '',
                command => 'ping',
            );

    if ($is_blocking) {
        return $cb->recv;
    }
    return;
}

sub _send_command_with_callback {
    my($self, $cb, %message_args) = @_;

    my $message = Nessy::Client::Message->new(serial => $MESSAGE_SERIAL++, %message_args);

    $self->_register_responder_for_message($cb, $message);
    $self->socket_watcher->push_write(json => $message);
}

sub _register_responder_for_message {
    my($self, $responder, $message) = @_;

    my $registry = $self->serial_responder_registry;
    $registry->{ $message->serial } = [ $responder, $message ];
}

sub _daemon_response_handler {
    my($self, $w, $message) = @_;

    my $registry = $self->serial_responder_registry;
    my $serial = $message->serial;
    my($responder, $orig_message) = @{ delete $registry->{$serial} };

    $self->bailout('no responder for message '.$message->serial) unless ($responder);

    $responder->($message);
}

sub _fail_outstanding_requests {
    my($self, $message) = @_;
    my $registry = $self->serial_responder_registry;
    foreach my $list ( values %$registry ) {
        my($responder, $orig_message) = @$list;

        $orig_message->fail;
        $orig_message->error_message($message);
        $responder->($orig_message);
    }
    $registry = {};
}


my $json_parser = JSON->new()->convert_blessed(1);
sub _create_socket_watcher {
    my $self = shift;
    my $socket = shift;

    my $self_copy = $self;
    Scalar::Util::weaken($self_copy);

    my $on_read = sub { shift->unshift_read(json => sub { $self_copy->_on_read_event(@_) }) };

    my $w = AnyEvent::Handle->new(
        fh => $socket,
        on_error => sub {
            my (undef, undef, $message) = @_;
            $self_copy->bailout($message);
        },
        on_read => $on_read,
        on_eof => sub { $self_copy->bailout('End of file while reading from client.') },
        json => $json_parser,
    );
}

sub _on_read_event {
    my($self, $w, $message) = @_;
    $message = Nessy::Client::Message->new(%$message);
    $self->_daemon_response_handler($w, $message);
}

sub bailout {
    my($self, $message) = @_;
    print STDERR "nessy: ",$message,"\n";
    $self->_fail_outstanding_requests($message);
    $self->socket_watcher(undef);
}

1;

=pod

=head1 NAME

Nessy::Client - Client API for the Nessy lock server

=head1 SYNOPSIS

  use Nessy::Client;

  my $client = Nessy::Client->new( url => 'http://nessy.server.example.org/' );

  my $claim = $client->claim( "my resource" );

  do_something_while_resource_is_locked();

  $claim->release();

=head1 Constructor

  my $client = Nessy::Client->new( url => $url,
                                   default_ttl => $ttl_seconds,
                                   default_timeout => $timeout_seconds,
                                   api_version => $version_string );

Create a new connection to the Nessy locking server.  C<url> is the top-level
URL the Nessy locking server is listening on.  C<default_ttl> is the default
time-to-live for all claims created through this client instance.
C<default_timeout> is the default command timeout for claims.  C<api_version>
is the dialect to use when talking to the server.

C<url> is the only required argument.  C<default_ttl> will default to 60
seconds.  C<default_timeout> will default to C<undef>, meaning that commands
will block for as long as necessary.  C<api_version> will default to "v1".

When a client instance is created, it will fork/exec a process
(L<Nessy::Daemon>) that manages claims for the creating process.

=head1 Methods

=over 4

=item api_version()

=item api_version($new_version)

Get or set the api_version.  Changing this attribute does not affect any
claims already created.

=item default_ttl

=item default_ttl( $new_default_ttl_seconds )

Get or the set the detault_ttl.  Changing this attribute does not affect any
claims already created.

=item default_timeout

=item default_timeout( $new_timeout_seconds )

Get or the set the default_timeout.  Changing this attribute does not affect any
claims already created.

=item claim()

  my $claim = $client->claim( $resource_name, %params);

Attempt to lock a named resource.  C<$resource_name> is a plain string.
C<%params> is an optional list of key/value pairs.  The default behavior is
for claim() to block until the named resource has been successfully claimed.
It returns an instance of L<Nessy::Claim> on success, and a false value on
failure, such as if the command timeout expires before the claim is locked.

Optional params are:

=over 2

=item ttl

Time-to-live for this claim.  Overrides the client's default_ttl.  When a
claim is made, it is valid on the server for this many seconds.  A claim's
ttl is refreshed periodicly by the Daemon process, and so can persist for
longer than the ttl.

=item timeout

Command timeout for this claim.  Overrides the client's default_ttl.

=item user_data

User data attached to this claim.  The server does not use it at all.
This data may be a reference to a deep data structure.  It must be serializable
with the JSON module.

=item cb

Normally claim() is a blocking function.  If cb is a function ref, then
claim() returns immediately.  When the claim is finalized as successful or not,
this function is called with the result as the only argument.  In order for
this asynchronous call to proceed, the main program must enter the AnyEvent
event loop.

=back

=item ping()

  my $worked = $client->ping()

  $client->ping( $result_coderef );

Returns true if the Daemon process is alive, false otherwise.  ping
accepts an optional callback coderef.  As with the claim() method, this
callback can only run if the main process enters the AnyEvent loop.

=item shutdown()

  $client->shutdown()

Shuts down the Daemon process.  Any claims still being held will be
abandoned.  The Daemon process will exit on its own if the parent
process terminates.

=back

=head1 SEE ALSO

L<Nessy::Claim>, L<Nessy::Daemon>

=head1 LICENSE

Copyright (C) The Genome Institute at Washington University in St. Louis.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Anthony Brummett E<lt>brummett@cpan.orgE<gt>

=cut
