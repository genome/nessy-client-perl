package Nessy::Client::TestWebProxy;

use strict;
use warnings;

use Carp;
use Socket;
use IO::Socket::INET;
use IO::Select;
use LWP::UserAgent;

sub new {
    my($class, $real_server_url) = @_;

    my $self = {};
    $self->{listen_socket} = $class->_make_new_socket;
    $self->{real_server_url} = $real_server_url;
    $self->{ua} = $class->_make_new_useragent;

    bless $self, $class;
}

sub ua { shift->{ua} }
sub socket { shift->{listen_socket} }
sub real_server_url { shift->{real_server_url} }

sub _make_new_socket {
    IO::Socket::INET->new(
        LocalAddr   => 'localhost',
        Proto       => 'tcp',
        Listen      => 5);
}

sub _make_new_useragent {
    my $ua = LWP::UserAgent->new();
    $ua->agent('Nessy::Client::TestWebProxy');
    return $ua;
}

my $url;
sub url {
    unless ($url) {
        my $self = shift;
        $url = sprintf('http://%s:%d',
                $self->socket->sockhost, $self->socket->sockport);
    }
    return $url;
}

sub host_and_port {
    my $self = shift;
    return sprintf('%s:%d',
        $self->socket->sockhost, $self->socket->sockport);
}

sub server_host_and_port {
    my $self = shift;
    my $url = $self->real_server_url;
    return join ':', $url =~ m|http://(.*):(.*)|;
}

sub do_one_request {
    my $self = shift;

    my $sock = $self->socket->accept();
    my $request_data = $self->_read_request_from_socket($sock);

    my $server_sock = $self->_connect_to_real_server();
    $server_sock->syswrite($request_data);

    my $response_data = $self->_read_request_from_socket($server_sock);
    $sock->syswrite($response_data);

    my $http_request = HTTP::Request->parse($request_data);
    my $http_response = HTTP::Response->parse($response_data);
    return ($http_request, $http_response);
}

sub _connect_to_real_server {
    my $self = shift;

    my ($peer) = $self->real_server_url =~ m#http://([^/]+)#;
    my $sock = IO::Socket::INET->new(
                    PeerAddr => $peer,
                    Proto => 'tcp')
    or Carp::croak "Failed to create socket: $!";
    return $sock;
}

sub _read_request_from_socket {
    my($self, $sock) = @_;

    my $sel = IO::Select->new($sock);
    my $buf = '';

    my $do_read = sub {
        my $bytes_to_read = shift || 1024;
        my $count = $sock->sysread($buf, $bytes_to_read, length($buf));
        unless (defined $count) {
            Carp::croak("Error reading from socket: $!");
        }
        return $count;
    };

    # First get the headers
    my($content_length, $body_length);
    while($sel->can_read) {
        $do_read->();
        if ($buf =~ m/\r\n\r\n(.*)/) {
            $body_length = length($1);
            # read in all the headers
            my($content_length) = $buf =~ m/^Content-Length: (\d+)/im;
            last;
        }
    }

    # now read in the body
    $content_length ||= 0;
    while ($body_length < $content_length) {
        my $read = $do_read->($content_length - $body_length);
        $body_length += $read;
    }

    return $buf;
}

1;
