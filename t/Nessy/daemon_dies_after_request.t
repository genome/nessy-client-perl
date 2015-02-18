use strict;
use warnings;

use Test::More tests => 3;
use Nessy::Client;
use Nessy::Client::Message;
use AnyEvent;
use AnyEvent::Handle;
use JSON;

# test that the client does not hang if the daemon's socket closes while we're
# waiting on a response

my $client = Nessy::Test::Client->new(url => 'http://localhost/');
ok($client, 'created new client');

subtest 'client does not block when daemon dies' => sub {
    plan tests => 4;

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

    local $SIG{ALRM} = sub { die "timed out" };
    alarm(30);
    my $warning_message;
    local $SIG{__WARN__} = sub { $warning_message = shift };
    my $claim_name = 'foo';
    my $claim = eval { $client->claim($claim_name) };
    alarm(0);

    ok(! $claim, "couldn't make a claim when the daemon closed its socket");
    ok(!$@, 'no exception');
    like($warning_message,
        qr(claim $claim_name at .* failed: Connection reset by peer),
        'warning message');
};

subtest 'daemon restarts after going away' => sub {
    plan tests => 5;

    # when it gets the claim message, send it back as successful
    my $respond_successfully = sub {
                my($watcher, $message_hash) = @_;
                my $message = Nessy::Client::Message->new(%$message_hash);
                ok($message, 'Got message from client to make a lock');
                $message->succeed;
                $watcher->push_write(json => $message);
            };

    alarm(30);

    my $w;
    my $json_parser = JSON->new()->convert_blessed();
    $client->on_fork(sub {
        ok(1, 'client is forking');

        $w = AnyEvent::Handle->new(
            fh => $client->daemon_to_client_sock,
            json => $json_parser,
        );
        $w->unshift_read(json => $respond_successfully);
    });

    my $claim = $client->claim('bar');
    ok($claim, 'made a claim');

    $w->unshift_read(json => $respond_successfully);
    ok($claim->release, 'release claim');

    alarm(0);
};

package Nessy::Test::Client;
use base 'Nessy::Client';

my($client_to_daemon_sock, $daemon_to_client_sock);
sub _make_socket_pair_for_daemon_comms {
    my $self = shift;
    ($client_to_daemon_sock, $daemon_to_client_sock) = $self->SUPER::_make_socket_pair_for_daemon_comms;
    return ($client_to_daemon_sock, $daemon_to_client_sock);
}

sub daemon_to_client_sock { $daemon_to_client_sock }

my $on_fork_cb;
sub on_fork {
    (undef, $on_fork_cb) = @_;
}
sub _fork {
    $on_fork_cb->() if $on_fork_cb;
    $$; # Don't fork
}

sub _close_unused_socket {} # don't close

sub _run_child_process {} 
