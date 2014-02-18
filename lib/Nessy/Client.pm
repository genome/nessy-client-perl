package Nessy::Client;

use strict;
use warnings;

use Nessy::Properties qw(pid socket socket_watcher serial_responder_registry api_version);

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

# The client process that acts as an intermediary between the client code
# and the lock server 

sub new {
    my($class, %params) = @_;

    my $ttl = $params{default_ttl} || $class->_default_ttl;
    my $api_version = $params{api_version} || $class->_default_api_version;

    my $url = $params{url} || Carp::croak('url is a required param');

    my($socket1, $socket2) = IO::Socket->socketpair(AF_UNIX, SOCK_STREAM, PF_UNSPEC);

    $_->autoflush(1) foreach ($socket1, $socket2);

    my $pid = _fork();
    if ($pid) {
        my $self = bless {}, $class;
        $self->api_version($api_version);
        $self->pid($pid);
        $self->serial_responder_registry({});

        my $watcher = $self->_create_socket_watcher($socket1);
        $self->socket_watcher($watcher);

        return $self;

    } elsif (defined $pid) {
        eval {
            $socket1->close();
            my $daemon_class = $class->_daemon_class_name;
            my $daemon = $daemon_class->new(
                                url => $url,
                                client_socket => $socket2,
                                default_ttl => $ttl,
                                api_version => $api_version);
            $daemon->start();
        };
        Carp::croak($@) if $@;
        exit;
    } else {
        Carp::croak("Can't fork: $!");
    }
}

sub _default_ttl { 60 } # seconds
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
    my($self, $resource_name, $data, $cb) = @_;

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
            $claim = $claim_class->new(
                    resource_name => $resource_name,
                    on_release => $on_release);
        } else {
            warn("claim $resource_name at $caller_location failed: ".$response->error_message);
        }
        $cb->($claim);
    };
    my $result = $self->_send_command_with_callback(
        $report_response,
        command => 'claim',
        resource_name => $resource_name,
        data => $data,
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
    $registry->{ $message->serial } = $responder;
}

sub _daemon_response_handler {
    my($self, $w, $message) = @_;

    my $registry = $self->serial_responder_registry;
    my $serial = $message->serial;
    my $responder = delete $registry->{$serial};

    $self->bailout('no responder for message '.$message->serial) unless ($responder);

    $responder->($message);
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
    Carp::croak($message);
}

1;
