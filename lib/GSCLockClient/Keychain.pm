package GSCLockClient::Keychain;

use strict;
use warnings;

use GSCLockClient::Properties qw(pid socket socket_watcher);

use GSCLockClient::Claim;
use GSCLockClient::Keychain::Daemon;

use Socket;
use IO::Socket;
use JSON qw();
use AnyEvent;
use AnyEvent::Handle;

# The keychain process that acts as an intermediary between the client code
# and the lock server 

sub new {
    my($class, %params) = @_;

    my($socket1, $socket2) = IO::Socket->socketpair(AF_UNIX, SOCK_STREAM, PF_UNSPEC);

    $_->autoflush(1) foreach ($socket1, $socket2);

    my $pid = fork();
    if ($pid) {
        my $self = bless {}, $class;
        $self->pid($pid);
        $self->socket($socket1);

        return $self;

    } elsif(defined $pid) {
        exit GSCLockClient::Keychain::Daemon->go(url => $params{url}, client_socket => $socket2);
    } else {
        die "Can't fork: $!";
    }
}

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
    return GSCLockClient::Claim->new(
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

my $json_parser = JSON->new();
sub _send_command_and_get_result {
    my $self = shift;
    my ($command) = @_;

    my $c = AnyEvent->condvar;
    my $watcher = $self->create_socket_watcher;

    $watcher->on_read( $c );

    $self->socket->print( $json_parser->encode($command) );
    $self->socket->print( $json_parser->encode({
        }));
    my $result = $c->recv;
    return unless $result->{result};
    return GSCLockClient::Claim->new(
        resource_name => $command->{resource_name},
        keychain  => $self,
    );
}


sub create_socket_watcher {
    my $self = shift;
    my $w = AnyEvent::Handle->new(
        fh => $self->socket,
        on_error => sub {
            my (undef, undef, $message) = @_;
            $self->bailout($message);
        },
        on_eof => sub { $self->bailout('End of file while reading from keychain.') },
        json => $json_parser,
    );

}

sub bailout {
}

1;
