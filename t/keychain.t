#!/usr/bin/env perl

use strict;
use warnings;

use Nessy::Keychain;

use POSIX ":sys_wait_h";
use AnyEvent;

use Test::More tests => 8;

test_constructor();
test_ping();
test_daemon_exits_from_destructor();
test_shutdown();

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
