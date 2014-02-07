#!/usr/bin/env perl

use strict;
use warnings;

use Nessy::Keychain::Daemon;

use Test::More tests => 5;
use Carp;
use JSON;
use Socket;
use IO::Socket;

test_constructor();
test_constructor_failures();

sub test_constructor_failures {
    my $daemon;

    $daemon = eval { Nessy::Keychain::Daemon->new() };
    ok($@, 'Calling constructor with no args generates an exception');

    $daemon = eval { Nessy::Keychain::Daemon->new(client_socket => 1) };
    like($@, qr(url is a required param), 'constructor throws exception when missing url param');

    $daemon = eval { Nessy::Keychain::Daemon->new(url => 1) };
    like($@, qr(client_socket is a required param), 'constructor throws exception when missing client_socket param');
}

sub test_constructor {
    my $daemon = Nessy::Keychain::Daemon->new(client_socket => 'abc', url => 1);
    ok($daemon, 'constructor');

    is_deeply($daemon->claims, {}, 'daemon claims() initialized to an empty hash');
}

{
    my $json = JSON->new();
    my($select, $socket);

    sub _new_test_daemon {
        my $daemon_socket;
        ($socket, $daemon_socket) = IO::Socket->socketpair(AF_UNIX, SOCK_STREAM, PF_UNSPEC);
        my $daemon = Nessy::Keychain::TestDaemon->new(client_socket => $daemon_socket, url => 'http://example.com');
        $select = IO::Select->new($socket);
        return $daemon;
    }

    sub _send_to_daemon {
        my($daemon, $msg) = @_;
        if (ref $msg) {
            $msg = $json->encode($msg);
        }

        while(length($msg) and $select->can_write(0)) {
            my $count = $socket->syswrite($msg);
            unless ($count) {
                Carp::croak("Couldn't write ".length($msg)." bytes of message: $!");
            }
            substr($msg, 0, $count, '');
        }
        if (length $msg) {
            Carp::croak("Send socket is full with ".length($msg)." bytes of message remaining");
        }
    }

    sub _read_from_daemon {
        my $daemon = shift;
        my $buf = '';

        while($select->can_read(0)) {
            my $count = $socket->sysread($buf, 1024, length($buf));
            unless ($count) {
                Carp::croak("Cound't read from daemon's socket: $!");
            }
        }
        return $buf;
    }
}

package Nessy::Keychain::TestDaemon;

use base 'Nessy::Keychain::Daemon';

sub _claim_class { return 'Nessy::Keychain::Daemon::FakeClaim' }

package Nessy::Keychain::Daemon::FakeClaim;

sub new {
    return bless {}, shift;
}

sub start {

}
