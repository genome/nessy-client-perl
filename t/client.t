#!/usr/bin/env perl

use strict;
use warnings;

use Nessy::Client;

use POSIX ":sys_wait_h";
use AnyEvent;

use Test::More tests => 18;

test_constructor();
test_ping();
test_daemon_exits_from_destructor();
test_shutdown();

test_claim_success();
test_claim_failure();

test_claim_release();
test_claim_release_with_callback();

sub test_constructor {
    my $fork_pid;
    no warnings 'redefine';
    local *Nessy::Client::_fork = sub {
        $fork_pid = CORE::fork();
        return $fork_pid;
    };
    
    my $client = Nessy::Client->new(url => 'http://example.org');
    ok($client, 'created client');
    ok($fork_pid, 'client forked');
    is($client->pid, $fork_pid, 'pid()');
    ok(kill(0, $fork_pid), 'daemon process exists');
}

sub test_ping {
    my $client = Nessy::Client->new(url => 'http://example.org');
    ok($client->ping, 'Client responds to ping');
}

sub test_shutdown {
    my $client = Nessy::Client->new(url => 'http://example.org');

    ok(kill(0, $client->pid), 'daemon is running before shutdown');

    my $pid = $client->pid;

    my $do_the_shutdown = sub {
        ok($client->shutdown, 'Client responds to shutdown');
    };

    my $killed = _wait_for_pid_to_exit_after($pid, 3, $do_the_shutdown);
    ok($killed, 'daemon actually exited');
}

sub test_daemon_exits_from_destructor {
    my $client = Nessy::Client->new(url => 'http://example.org');

    my $pid = $client->pid;

    $client->ping;  # wait for it to actually get going

    my $killed = _wait_for_pid_to_exit_after($pid, 3, sub { undef $client });
    ok($killed, 'daemon process exits when client goes away');
}

sub _wait_for_pid_to_exit_after {
    my($pid, $timeout, $action) = @_;

    my $killed;
    local $SIG{CHLD} = sub {
        my $child_pid = waitpid($pid, WNOHANG);
        $killed = 1 if $child_pid == $pid;
    };
    local $SIG{ALRM} = sub { $killed = 0; print "alarm\n"; };

    alarm($timeout);
    $action->();
    while(! defined $killed) {
        select(undef,undef,undef,undef);
    }
    alarm(0);
    return $killed;
}

sub test_claim_success {
    local $Nessy::TestClient::Daemon::claim_should_fail = 0;
    my $client = Nessy::TestClient->new(url => 'http://example.org');

    my $resource_name = 'foo';
    my $data = { some => 'data', structure => [ 'has', 'nested', 'data' ] };

    my $claim = $client->claim($resource_name, user_data => $data);

    isa_ok($claim, 'Nessy::Claim');
    is($claim->resource_name, $resource_name, 'claim resource');
}

sub test_claim_failure {
    local $Nessy::TestClient::Daemon::claim_should_fail = 1;
    my $client = Nessy::TestClient->new(url => 'http://example.org');

    my $resource_name = 'foo';
    my $data = { some => 'data', structure => [ 'has', 'nested', 'data' ] };

    my $got_warning = '';
    local $SIG{__WARN__} = sub { $got_warning = shift };
    my $claim = $client->claim($resource_name, user_data => $data);

    is($claim, undef, 'failed claim');
    my $this_file = __FILE__;
    like($got_warning, qr(claim $resource_name at $this_file:\d+ failed: in-test failure), 'expected warning');
}

sub test_claim_release {
    my $client = Nessy::TestClient->new(url => 'http://example.org');

    my $resource_name = 'foo';

    my $claim = $client->claim($resource_name);

    isa_ok($claim, 'Nessy::Claim');

    ok($claim->release(), 'release claim');
}

sub test_claim_release_with_callback {
    my $client = Nessy::TestClient->new(url => 'http://example.org');

    my $resource_name = 'foo';

    my $claim = $client->claim($resource_name);

    isa_ok($claim, 'Nessy::Claim');

    my $cv = AnyEvent->condvar;
    is($claim->release($cv), undef, 'release claim with callback returns undef');

    is($cv->recv, 1, 'release-supplied callback was called');
}





package Nessy::TestClient;

use base 'Nessy::Client';

sub _daemon_class_name { 'Nessy::TestClient::Daemon' }

package Nessy::TestClient::Daemon;

use base 'Nessy::Daemon';

sub _claim_class { 'Nessy::TestDaemon::Claim' }

our($claim_should_fail, $release_should_fail);

sub claim {
    my($self, $message) = @_;
    if ($claim_should_fail) {
        $self->claim_failed(undef, $message, 'in-test failure');
    } else {
        $self->SUPER::claim($message);
        $self->claim_succeeded(undef, $message);
    }
    1;
}

sub release {
    my($self, $message) = @_;
    if ($release_should_fail) {
        $self->release_failed(undef, $message, 'in-test failure');
    } else {
        $self->release_succeeded(undef, $message);
    }
    1;
}

sub run { shift->start }  # don't exec a new process
sub add_claim { }
sub remove_claim { }

package Nessy::TestDaemon::Claim;

use base 'Nessy::Daemon::Claim';

sub start {}
sub release {}
