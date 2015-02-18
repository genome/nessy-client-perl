use strict;
use warnings;

use Test::More tests => 5;
use Nessy::Client;
use AnyEvent;

# test that the client does not hang if the daemon's socket closes while we're
# waiting on a response

my $client = Nessy::Test::Client->new(url => 'http://localhost/');
ok($client, 'created new client');

my $w;
$w = AnyEvent->io(fh => $client->daemon_to_client_sock,
             poll => 'r',
             # when the client sends the daemon a lock request, close
             # the socket to simulate the daemon going away
             cb => sub {
                        ok(1, 'Got message from client to make a lock');
                        $client->daemon_to_client_sock->close(),
                        undef $w;
                      },
        );

$SIG{ALRM} = sub { die "timed out" };
alarm(30);
my $warning_message;
$SIG{__WARN__} = sub { $warning_message = shift };
my $claim_name = 'foo';
my $claim = eval { $client->claim($claim_name) };

ok(! $claim, "couldn't make a claim when the daemon closed its socket");
ok(!$@, 'no exception');
like($warning_message,
    qr(claim $claim_name at .* failed: Connection reset by peer),
    'warning message');


package Nessy::Test::Client;
use base 'Nessy::Client';

my($client_to_daemon_sock, $daemon_to_client_sock);
sub _make_socket_pair_for_daemon_comms {
    my $self = shift;
    ($client_to_daemon_sock, $daemon_to_client_sock) = $self->SUPER::_make_socket_pair_for_daemon_comms;
    return ($client_to_daemon_sock, $daemon_to_client_sock);
}

sub daemon_to_client_sock { $daemon_to_client_sock }

sub _fork { $$ }  # Don't fork
sub _close_unused_socket {} # don't close

sub _run_child_process {} 
