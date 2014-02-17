#!/usr/bin/env perl

use strict;
use warnings;

use Nessy::Keychain;

use POSIX ":sys_wait_h";
use AnyEvent;

use Test::More tests => 13;

test_constructor();
test_ping();
test_daemon_exits_from_destructor();
test_shutdown();

test_claim_success();
test_claim_failure();

test_claim_release();

sub test_constructor {
    my $fork_pid;
    no warnings 'redefine';
    local *Nessy::Keychain::_fork = sub {
        $fork_pid = CORE::fork();
        return $fork_pid;
    };
    
    my $keychain = Nessy::Keychain->new(url => 'http://example.org');
    ok($keychain, 'created keychain');
    ok($fork_pid, 'keychain forked');
    is($keychain->pid, $fork_pid, 'pid()');
    ok(kill(0, $fork_pid), 'daemon process exists');
}

sub test_ping {
    my $keychain = Nessy::Keychain->new(url => 'http://example.org');
    ok($keychain->ping, 'Keychain responds to ping');
}

sub test_shutdown {
    my $keychain = Nessy::Keychain->new(url => 'http://example.org');

    my $pid = $keychain->pid;

    my $do_the_shutdown = sub {
        ok($keychain->shutdown, 'Keychain responds to shutdown');
    };

    my $killed = _wait_for_pid_to_exit_after($pid, 3, $do_the_shutdown);
    ok($killed, 'daemon actually exited');
}

sub test_daemon_exits_from_destructor {
    my $keychain = Nessy::Keychain->new(url => 'http://example.org');

    my $pid = $keychain->pid;

    $keychain->ping;  # wait for it to actually get going

    my $killed = _wait_for_pid_to_exit_after($pid, 3, sub { undef $keychain });
    ok($killed, 'daemon process exits when keychain goes away');
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
    local $Nessy::TestKeychain::Daemon::claim_should_fail = 0;
    my $keychain = Nessy::TestKeychain->new(url => 'http://example.org');

    my $resource_name = 'foo';
    my $data = { some => 'data', structure => [ 'has', 'nested', 'data' ] };

    my $claim = $keychain->claim($resource_name, $data);

    isa_ok($claim, 'Nessy::Claim');
    is($claim->resource_name, $resource_name, 'claim resource');
}

sub test_claim_failure {
    local $Nessy::TestKeychain::Daemon::claim_should_fail = 1;
    my $keychain = Nessy::TestKeychain->new(url => 'http://example.org');

    my $resource_name = 'foo';
    my $data = { some => 'data', structure => [ 'has', 'nested', 'data' ] };

    my $claim = $keychain->claim($resource_name, $data);

    is($claim, undef, 'failed claim');
}

sub test_claim_release {
    my $keychain = Nessy::TestKeychain->new(url => 'http://example.org');

    my $resource_name = 'foo';

    my $claim = $keychain->claim($resource_name);

    isa_ok($claim, 'Nessy::Claim');

    ok($claim->release(), 'release claim');
}





package Nessy::TestKeychain;

use base 'Nessy::Keychain';

sub _daemon_class_name { 'Nessy::TestKeychain::Daemon' }

package Nessy::TestKeychain::Daemon;

use base 'Nessy::Keychain::Daemon';

our($claim_should_fail, $release_should_fail);

sub claim {
    my($self, $message) = @_;
    if ($claim_should_fail) {
        $self->claim_failed(undef, $message, 'in-test failure');
    } else {
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

sub add_claim { }
sub remove_claim { }
