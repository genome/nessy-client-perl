package Nessy::Keychain;

use strict;
use warnings;

use Nessy::Properties qw(pid socket socket_watcher serial_responder_registry);

use Nessy::Claim;
use Nessy::Keychain::Daemon;

use Carp;
use Socket;
use IO::Socket;
use JSON qw();
use AnyEvent;
use AnyEvent::Handle;
use Scalar::Util;

my $MESSAGE_SERIAL = 1;

# The keychain process that acts as an intermediary between the client code
# and the lock server 

sub new {
    my($class, %params) = @_;

    my $ttl = $params{default_ttl} || $class->_default_ttl;

    my($socket1, $socket2) = IO::Socket->socketpair(AF_UNIX, SOCK_STREAM, PF_UNSPEC);

    $_->autoflush(1) foreach ($socket1, $socket2);

    my $pid = _fork();
    if ($pid) {
        my $self = bless {}, $class;
        $self->pid($pid);
        $self->serial_responder_registry({});

        my $watcher = $self->_create_socket_watcher($socket1);
        $self->socket_watcher($watcher);

        return $self;

    } elsif (defined $pid) {
        eval {
            $socket1->close();
            my $daemon_class = $class->_daemon_class_name;
            my $daemon = $daemon_class->new(url => $params{url}, client_socket => $socket2, default_ttl => $ttl);
            $daemon->start();
        };
        Carp::croak($@) if $@;
        exit;
    } else {
        Carp::croak("Can't fork: $!");
    }
}

sub _default_ttl { 60 } # seconds

sub _daemon_class_name { 'Nessy::Keychain::Daemon' }

sub _fork { fork }

sub shutdown {
    my $self = shift;
    my $timeout = shift || 0;

    my $pid = $self->pid;
    kill('TERM', $pid);

    local $SIG{ALRM} = $self->_shutdown_timeout_sub;

    alarm($timeout);
    waitpid($pid, 0);
    alarm(0);
}

sub _shutdown_timeout_sub {
    return sub {};
}

sub claim {
    my($self, $resource_name, $data) = @_;

    my $result = $self->_send_command_and_get_result({
        command => 'claim',
        resource_name => $resource_name,
        data => $data,
    });

    return unless $result->{result};
    return Nessy::Claim->new(
        resource_name => $resource_name,
        keychain  => $self,
    );
}

sub release {
    my $self = shift;
    my ($resource_name) = @_;

    my $result = $self->_send_command_and_get_result({
        command => 'release',
        resource_name => $resource_name,
    });
    return $result->{result} eq 'success';
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

    my $message = Nessy::Keychain::Message->new(serial => $MESSAGE_SERIAL++, %message_args);

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
        on_eof => sub { $self_copy->bailout('End of file while reading from keychain.') },
        json => $json_parser,
    );
}

sub _on_read_event {
    my($self, $w, $message) = @_;
    $message = Nessy::Keychain::Message->new(%$message);
    $self->_daemon_response_handler($w, $message);
}

sub bailout {
    my($self, $message) = @_;
    Carp::croak($message);
}

1;
