#!/usr/bin/env perl

use strict;
use warnings;

use Nessy::Keychain;

use POSIX ":sys_wait_h";
use AnyEvent;

use Test::More tests => 6;

test_constructor();
test_ping();
test_daemon_exits_from_destructor();

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

sub test_daemon_exits_from_destructor {
    my $keychain = Nessy::Keychain->new(url => 'http://example.org');

    my $pid = $keychain->pid;

    $keychain->ping;

    undef $keychain;

    my $killed = _wait_for_pid_to_exit($pid, 3);
    ok($killed, 'daemon process exits when keychain goes away');
}

sub _wait_for_pid_to_exit {
    my($pid, $timeout) = @_;

    my $killed;
    local $SIG{CHLD} = sub {
        my $child_pid = waitpid($pid, WNOHANG);
        print "child $child_pid\n";
        $killed = 1 if $child_pid == $pid;
    };
    local $SIG{ALRM} = sub { $killed = 0; print "alarm\n"; };

    alarm($timeout);
    while(! defined $killed) {
        select(undef,undef,undef,undef);
    }
    alarm(0);
    return $killed;
}
