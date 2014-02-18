#!/usr/bin/env perl

use strict;
use warnings;

use Nessy::Daemon;
use Nessy::Client::Message;

use Test::More tests => 72;
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
test_make_claim_failure();
test_release_claim_success_and_failure();

test_daemon_exits_when_socket_closes();

sub test_constructor_failures {
    my $daemon;

    $daemon = eval { Nessy::Daemon->new() };
    ok($@, 'Calling constructor with no args generates an exception');

    my %all_params = ( client_socket => 1, url => 1, default_ttl => 1, api_version => 1 );
    foreach my $omit ( keys %all_params ) {
        my %params = %all_params;
        delete $params{$omit};
        $daemon = eval { Nessy::Daemon->new(%params) };
        like($@, qr($omit is a required param), "constructor throws exception when missing $omit param");
    }
}

sub test_constructor {
    my $fake_socket = IO::Handle->new();
    my $daemon = Nessy::Daemon->new(
                    client_socket => $fake_socket,
                    url => 1,
                    default_ttl => 1,
                    api_version => 'v1');
    ok($daemon, 'constructor');

    is_deeply($daemon->claims, {}, 'daemon claims() initialized to an empty hash');
}

sub test_start {
    my ($test_handle,$not_needed) = IO::Socket->socketpair(
        AF_UNIX, SOCK_STREAM, PF_UNSPEC);
    my $daemon = Nessy::Daemon->new(
                        client_socket => $test_handle,
                        url => 'http://example.org',
                        default_ttl => 1,
                        api_version => 'v1');

    my $cv = AnyEvent->condvar;
    $cv->send(1);

    ok($daemon->start($cv), 'start() as an instance method method');

    ok($daemon->client_watcher, 'client watcher created');
}

sub _unexpected_fatal_error { my($obj, $message) = @_; Carp::croak("unexpected fatal error: $message") };

sub test_add_remove_claim {
    my $daemon = _new_test_daemon();

    my $test_claim_foo = Nessy::Daemon::FakeClaim->new(
        resource_name => 'foo',
        client => $daemon,
        on_fatal_error => \&_unexpected_fatal_error,
        api_version => 'v1');
    my $test_claim_bar = Nessy::Daemon::FakeClaim->new(
        resource_name => 'bar',
        client => $daemon,
        on_fatal_error => \&_unexpected_fatal_error,
        api_version => 'v1');
    my $missing_claim_baz = Nessy::Daemon::FakeClaim->new(
        resource_name => 'baz',
        client => $daemon,
        on_fatal_error => \&_unexpected_fatal_error,
        api_version => 'v1');

    ok( $daemon->add_claim($test_claim_foo),
        'add_claim() foo');
    ok( $daemon->add_claim($test_claim_bar),
        'add_claim() bar');

    ok(! $daemon->remove_claim($missing_claim_baz),
        'cannot remove unknown claim baz');

    eval {
        $daemon->add_claim(
            Nessy::Daemon::FakeClaim->new(
                resource_name => 'foo',
                client => $daemon,
                on_fatal_error => \&_unexpected_fatal_error,
                api_version => 'v1')
            );
    };
    like($@, qr(Attempted to add claim foo when it already exists), 'cannot double add the same claim');

    is_deeply( $daemon->claims(),
        { foo => $test_claim_foo, bar => $test_claim_bar },
        'claims() returns known claims');

    is($daemon->remove_claim($test_claim_foo), $test_claim_foo, 'remove claim foo');
    ok(! $daemon->remove_claim($test_claim_foo), 'cannot double remove the same claim');

    is_deeply( $daemon->claims(),
        { bar => $test_claim_bar },
        'claims() returns known claim bar');

    is($daemon->lookup_claim('bar'), $test_claim_bar, 'lookup_claim()');
    is($daemon->lookup_claim('missing'), undef, 'lookup_claim() with non-existent resource_name');
}

sub test_make_claim {
    my $daemon = _new_test_daemon();

    my $message = Nessy::Client::Message->new(
                        resource_name => 'foo',
                        command => 'claim',
                        serial => 1,
                    );
    _send_to_socket($message);

    my $cv = AnyEvent->condvar();
    local $Nessy::Daemon::FakeClaim::on_start_cb = sub { $cv->send; 1; };
    my $expected_claim_location_url = 'something';
    @Nessy::Daemon::FakeClaim::next_http_response = ([
            '',
            {   Status => 201,
                location => $expected_claim_location_url,
            }]);

    _event_loop($daemon, $cv);

    my $response = _read_from_socket();
    
    my %expected = ( resource_name => 'foo', command => 'claim');
    foreach my $key ( keys %expected ) {
        is($response->$key, $expected{$key}, "Response key $key");
    }
    ok($response->is_succeeded, 'successful response');

    my $claim = $daemon->lookup_claim('foo');
    ok($claim, 'daemon created claim for resource_name foo');
    ok($claim->_start_called, 'state machine was started for claim');
    is($claim->claim_location_url, $expected_claim_location_url, 'claim location url');

    eval { _read_from_socket() };
    like($@, qr(No data read from socket), 'Daemon has no more messages for us');

    $Nessy::TestDaemon::destroy_called = 0;
    undef $daemon;
    ok($Nessy::TestDaemon::destroy_called, 'Daemon destroyed');

    eval { _read_from_socket() };
    like($@, qr(No data read from socket), 'After destruction, daemon has no more messages for us');
}

sub test_make_claim_failure {
    my $daemon = _new_test_daemon();

    my $message = Nessy::Client::Message->new(
                        resource_name => 'foo',
                        command => 'claim',
                        serial => 1,
                    );
    _send_to_socket($message);

    my $cv = AnyEvent->condvar();
    local $Nessy::Daemon::FakeClaim::on_start_cb = sub { $cv->send; 0; };
    @Nessy::Daemon::FakeClaim::next_http_response = ([
        '',
        { Status => 400 },
    ]);

    _event_loop($daemon, $cv);

    my $response = _read_from_socket();
    
    my %expected = ( resource_name => 'foo', command => 'claim', result => 'failed' );
    foreach my $key ( keys %expected ) {
        is($response->$key, $expected{$key}, "Response key $key");
    }

    my $claim = $daemon->lookup_claim('foo');
    ok(! $claim, 'daemon did not create claim for resource_name foo');

    eval { _read_from_socket() };
    like($@, qr(No data read from socket), 'Daemon has no more messages for us');

    $Nessy::TestDaemon::destroy_called = 0;
    undef $daemon;
    ok($Nessy::TestDaemon::destroy_called, 'Daemon destroyed');

    eval { _read_from_socket() };
    like($@, qr(No data read from socket), 'After destruction, daemon has no more messages for us');
}

sub test_release_claim_success_and_failure {
    _test_release_claim_success_and_failure($_) foreach ( 204, 400, 404, 409 );
}

sub _test_release_claim_success_and_failure {
    my($response_code) = @_;

    my $daemon = _new_test_daemon();
    my $fatal_error = 0;
    my $claim = Nessy::Daemon::FakeClaim->new(
                    client => $daemon,
                    on_fatal_error => sub { $fatal_error++ },
                    api_version => 'v1');

    ok($claim->state('active'), 'Set claim active');
    ok($daemon->add_claim($claim), "Add claim to client for response code $response_code");

    my $message = Nessy::Client::Message->new(
                        resource_name => $claim->resource_name,
                        command => 'release',
                        serial => 1,
                    );
    _send_to_socket($message);

    my $cv = AnyEvent->condvar();
    local $Nessy::Daemon::FakeClaim::on_release_cb = sub { $cv->send; 1; };

    @Nessy::Daemon::FakeClaim::next_http_response = ([
        '',
        { Status => $response_code },
    ]);
    _event_loop($daemon, $cv);

    my $response = _read_from_socket();

    my %expected = ( resource_name => $claim->resource_name, command => 'release');
    foreach my $key ( keys %expected ) {
        is($response->$key, $expected{$key}, "response key $key $expected{$key}");
    }

    my $result_method = $response_code =~ m/^2/ ? 'is_succeeded' : 'is_failed';
    ok($response->$result_method, $result_method);

    ok(! $daemon->lookup_claim( $claim->resource_name ), 'Daemon no longer holds the claim');
    ok($claim->_release_called, 'Claim had release() called');

    eval { _read_from_socket() };
    like($@, qr(No data read from socket), 'Daemon has no more messages for us');

    is($fatal_error, 0, 'no fatal errors');
}

sub test_daemon_exits_when_socket_closes {
    my $daemon = _new_test_daemon();

    _close_socket();

    _event_loop($daemon);

    is($daemon->exit_cleanly_was_called, 1, 'daemon calls exit_cleanly() when socket closes');
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

    sub _close_socket {
        $socket->close();
    }

    sub _new_test_daemon {
        my $daemon_socket;
        ($socket, $daemon_socket) = IO::Socket->socketpair(AF_UNIX, SOCK_STREAM, PF_UNSPEC);
        $select = IO::Select->new($socket);

        my $daemon = Nessy::TestDaemon->new(
                            client_socket => $daemon_socket,
                            url => 'http://example.com',
                            default_ttl => 1,
                            api_version => 'v1');
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
            unless (defined $count) {
                Carp::croak("Cound't read from daemon's socket: $!");
            }
            last unless $count;
        }
        Carp::croak("No data read from socket") unless length($buf);
        return Nessy::Client::Message->from_json($buf);
    }
}

package Nessy::TestDaemon;

use base 'Nessy::Daemon';

sub _claim_class { return 'Nessy::Daemon::FakeClaim' }

sub new {
    our $destroy_called = 0;
    shift->SUPER::new(@_);
}

sub DESTROY {
    our $destroy_called = 1;
    shift->SUPER::DESTROY;
}

sub _exit_cleanly {
    my $self = shift;
    $self->{_exit_cleanly_called} = 1;
    $self->SUPER::_exit_cleanly(@_);
}
sub exit_cleanly_was_called {
    return shift->{_exit_cleanly_called};
}
sub _exit {} # don't exit

package Nessy::Daemon::FakeClaim;

use base 'Nessy::Daemon::Claim';

our($on_start_cb, $on_release_cb);

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
    $self->{_start_called} = 1;
    $self->SUPER::start(@_);
    $on_start_cb->() if $on_start_cb;
}

our @next_http_response;
sub _send_http_request {
    my $cb = pop;
    my($self, $http_method, $url, %params) = @_;

    my @args;
    if ($Nessy::TestDaemon::destroy_called) {
        @args = ('in shutdown', { Status => 204 });

    } elsif (@next_http_response) {
        @args = @{ shift @next_http_response };

    } else {
        Carp::croak("Asked to send http request $http_method to $url, but there is no prepared \@next_http_response");
    }

    return $cb->(@args);
}

sub _start_called {
    return shift->{_start_called};
}

sub release {
    my $self = shift;
    $self->SUPER::release(@_);
    $self->{_release_called} = 1;
    $on_release_cb->() if $on_release_cb;
}

sub _release_called {
    return shift->{_release_called};
}

