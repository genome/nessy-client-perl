#!/usr/bin/env perl

use strict;
use warnings;

use Nessy::Keychain;

use Test::More tests => 5;

our @forked_pids = ();

test_constructor();
test_ping();

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

