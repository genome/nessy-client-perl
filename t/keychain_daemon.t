#!/usr/bin/env perl

use strict;
use warnings;

use Nessy::Keychain::Daemon;
use Nessy::Keychain::Message;

use Test::More tests => 15;
use Carp;
use JSON;
use Socket;
use IO::Socket;
use IO::Select;
use IO::Handle;
use AnyEvent;

test_constructor();
test_constructor_failures();

test_start();

test_add_remove_claim();

test_make_claim();

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
    my $fake_socket = IO::Handle->new();
    my $daemon = Nessy::Keychain::Daemon->new(client_socket => $fake_socket, url => 1);
    ok($daemon, 'constructor');

    is_deeply($daemon->claims, {}, 'daemon claims() initialized to an empty hash');
}

sub test_start {
    my $test_handle = IO::Handle->new();
    my $daemon = Nessy::Keychain::Daemon->new(client_socket => $test_handle, url => 'http://example.org');

    my $cv = AnyEvent->condvar;
    $cv->send(1);

    ok($daemon->start($cv), 'start() as an instance method method');

    ok($daemon->client_watcher, 'client watcher created');
}

sub test_add_remove_claim {
    my $daemon = _new_test_daemon();

    my $test_claim_foo = Nessy::Keychain::Daemon::FakeClaim->new(
        resource_name => 'foo', keychain => $daemon);
    my $test_claim_bar = Nessy::Keychain::Daemon::FakeClaim->new(
        resource_name => 'bar', keychain => $daemon);

    ok( $daemon->add_claim('foo', $test_claim_foo),
        'add_claim() foo');
    ok( $daemon->add_claim('bar', $test_claim_bar),
        'add_claim() bar');

    ok(! $daemon->remove_claim('baz'),
        'cannot remove unknown claim baz');

    eval {
        $daemon->add_claim('foo',
            Nessy::Keychain::Daemon::FakeClaim->new(
                resource_name => 'foo', keychain => $daemon))
    };
    like($@, qr(Attempted to add claim foo when it already exists), 'cannot double add the same claim');

    is_deeply( $daemon->claims(),
        { foo => $test_claim_foo, bar => $test_claim_bar },
        'claims() returns known claims');

    is($daemon->remove_claim('foo'), $test_claim_foo, 'remove claim foo');
    ok(! $daemon->remove_claim('foo'), 'cannot double remove the same claim');

    is_deeply( $daemon->claims(),
        { bar => $test_claim_bar },
        'claims() returns known claim bar');

    is($daemon->lookup_claim('bar'), $test_claim_bar, 'lookup_claim()');
    is($daemon->lookup_claim('missing'), undef, 'lookup_claim() with non-existent resource_name');
}

sub test_make_claim {
    my $daemon = _new_test_daemon();

    my $message = Nessy::Keychain::Message->new(
                        resource_name => 'foo',
                        command => 'claim',
                    );
    _send_to_socket($message);

    my $cv = AnyEvent->condvar();
    local $Nessy::Keychain::Daemon::FakeClaim::on_start_cb = sub { $cv->send };
    _event_loop($daemon, $cv);

    my $response = _read_from_socket();
    
    my %expected = ( resource_name => 'foo', command => 'claim', result => 'succeeded' );
    my $is_ok = 1;
    foreach my $key ( %expected ) {
        $is_ok = 0 if ($response->$key ne $expected{$key});
    }
    ok($is_ok, 'response');

    my $claim = $daemon->lookup_claim('foo');
    ok($claim, 'daemon created claim for resource_name foo');
    ok($claim->_start_called, 'state machine was started for claim');
    $Nessy::Keychain::TestDaemon::destroy_called = 0;
    undef $daemon;
    ok($Nessy::Keychain::TestDaemon::destroy_called, 'Daemon destroyed');
}

sub _event_loop {
    my($daemon, $cv) = @_;

    $cv ||= AnyEvent->condvar;
    local $SIG{ALRM} = sub { note('_event_loop waited too long'); $cv->send() };

    alarm(3) unless defined &DB::DB;
    my $rv = $daemon->start($cv);
    alarm(0);
    return $rv;

}

{
    my $json; BEGIN { $json = JSON->new->convert_blessed(1); }
    my($select, $socket);

    sub _new_test_daemon {
        my $daemon_socket;
        ($socket, $daemon_socket) = IO::Socket->socketpair(AF_UNIX, SOCK_STREAM, PF_UNSPEC);
        $select = IO::Select->new($socket);

#$socket->syswrite("test message");
#my $c = $daemon_socket->sysread(my $read, 1024);
#print "read $c back >>$read<<\n";




print "created my socket fd ",fileno($socket)," daemon socket ",fileno($daemon_socket),"\n";
        my $daemon = Nessy::Keychain::TestDaemon->new(client_socket => $daemon_socket, url => 'http://example.com');
        return $daemon;
    }

    sub _send_to_socket {
        my($msg) = @_;
        if (ref $msg) {
            $msg = $json->encode($msg);
        }

        while(length($msg) and $select->can_write(0)) {
            my $count = $socket->syswrite($msg);
            unless ($count) {
                Carp::croak("Couldn't write ".length($msg)." bytes of message: $!");
            }
print "wrote $count bytes to fd ",fileno($socket),"\n";
            substr($msg, 0, $count, '');
        }
        if (length $msg) {
            Carp::croak("Send socket is full with ".length($msg)." bytes of message remaining");
        }
    }

    sub _read_from_socket {
        my $buf = '';

        while($select->can_read(0)) {
            my $count = $socket->sysread($buf, 1024, length($buf));
            unless ($count) {
                Carp::croak("Cound't read from daemon's socket: $!");
            }
        }
        Carp::croak("No data read from socket") unless length($buf);
        return Nessy::Keychain::Message->from_json($buf);
    }
}

package Nessy::Keychain::TestDaemon;

use base 'Nessy::Keychain::Daemon';

sub _claim_class { return 'Nessy::Keychain::Daemon::FakeClaim' }
sub DESTROY {
    our $destroy_called = 1;
    shift->SUPER::DESTROY;
}

package Nessy::Keychain::Daemon::FakeClaim;

use base 'Nessy::Keychain::Daemon::Claim';

our $on_start_cb;

sub new {
    my $class = shift;
    my %params = (
        url           => 'http://example.org',
        resource_name => 'foo',
        ttl           => 10,
        @_,
    );
    return $class->SUPER::new(%params);
}

sub start {
    my $self = shift;
print "Fake claim is starting!!\n";
    $self->{_start_called} = 1;
    $on_start_cb->($self) if ($on_start_cb);
    $self->keychain->claim_succeeded( $self->resource_name );
}

sub _start_called {
    return shift->{_start_called};
}

