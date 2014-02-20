package Nessy::Client::TestWebServer;

use strict;
use warnings FATAL => qw(all);

use IO::Pipe;
use Carp;
use Storable;
use JSON;
use Socket qw(IPPROTO_TCP TCP_NODELAY);
use IO::Socket::INET;

use HTTP::Server::PSGI;

my $SERVER_SOCKET;

sub new {
    my($class, @responses) = @_;

    unless ($SERVER_SOCKET) {
        $SERVER_SOCKET = $class->_make_new_socket();
    }

    my $pipe = IO::Pipe->new();
    if (my $pid = fork()) {
        $pipe->reader;
        my $self = { pipe => $pipe, pid => $pid };
        return bless $self, $class;

    } elsif (defined $pid) {
        $pipe->writer;
        _run_web_server($SERVER_SOCKET, $pipe, @responses);
        exit;

    } else {
        Carp::croak("fork() failed: $!");
    }
}

sub get_connection_details {
    my $class = shift;

    unless ($SERVER_SOCKET) {
        $SERVER_SOCKET = $class->_make_new_socket();
    }
    return ($SERVER_SOCKET->sockhost, $SERVER_SOCKET->sockport)
}

sub _make_new_socket {
    return IO::Socket::INET->new(
        LocalAddr   => 'localhost',
        Proto       => 'tcp',
        Listen      => 5);
}

sub join {
    my $self = shift;

    my $pipe = $self->{pipe};
    my $data = join('', <$pipe>);

    waitpid($self->{pid}, 0);
    my $list = Storable::thaw($data);
    return @$list;
}

sub _run_web_server {
    my($socket, $result_pipe, @responses) = @_;

    my $server = _make_web_server($socket);

    my @envs;
    $server->run(sub {
        my $env = shift;
        $env->{__BODY__} = _get_request_body( $env->{'psgi.input'} );
        delete $env->{'psgi.input'};
        delete $env->{'psgi.errors'};
        delete $env->{'psgix.io'};

        my $response = shift @responses;
        push @envs, $env;
        $env->{'psgix.harakiri.commit'} = 1 unless(@responses);
        return $response;
    });

    _send_result($result_pipe, @envs);
}

sub _send_result {
    my($result_pipe, @data) = @_;

    my $encoded = Storable::freeze(\@data);
    print $result_pipe $encoded;
    close $result_pipe;
}
    
        
sub _get_request_body {
    my ($psgi_input) = @_;

    my $body = '';
    while ($psgi_input->read($body, 1024, length($body))) {}

    return JSON::decode_json($body);
}


sub _make_web_server {
    my $socket = shift;

    my $server = HTTP::Server::PSGI->new(
        host => $socket->sockaddr,
        port => $socket->sockport,
        timeout => 120);

    $server->{listen_sock} = $socket;
    return $server;
}


sub _fixed_accept_loop {
    # TODO handle $max_reqs_per_child
    my($self, $app, $max_reqs_per_child) = @_;
    my $proc_req_count = 0;

    $app = Plack::Middleware::ContentLength->wrap($app);

    while (! defined $max_reqs_per_child || $proc_req_count < $max_reqs_per_child) {
        local $SIG{PIPE} = 'IGNORE';
        if (my $conn = $self->{listen_sock}->accept) {
            $conn->setsockopt(IPPROTO_TCP, TCP_NODELAY, 1)
                or die "setsockopt(TCP_NODELAY) failed:$!";
            ++$proc_req_count;
            my $env = {
                SERVER_PORT => $self->{port},
                SERVER_NAME => $self->{host},
                SCRIPT_NAME => '',
                REMOTE_ADDR => $conn->peerhost,
                'psgi.version' => [ 1, 1 ],
                'psgi.errors'  => *STDERR,
                'psgi.url_scheme' => 'http',
                'psgi.run_once'     => Plack::Util::FALSE,
                'psgi.multithread'  => Plack::Util::FALSE,
                'psgi.multiprocess' => Plack::Util::FALSE,
                'psgi.streaming'    => Plack::Util::TRUE,
                'psgi.nonblocking'  => Plack::Util::FALSE,
                'psgix.input.buffered' => Plack::Util::TRUE,
                'psgix.harakiri'    => Plack::Util::TRUE,
                'psgix.io'          => $conn,
            };

            $self->handle_connection($env, $conn, $app);
            $conn->close;
            last if $env->{'psgix.harakiri.commit'};
        }
    }
}

BEGIN {
    require Plack;
    if ($Plack::VERSION < 1.0004) {
        no warnings 'redefine';
        *HTTP::Server::PSGI::accept_loop = \&_fixed_accept_loop;
    }
}

1;
