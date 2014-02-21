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

sub do_one_request {
    my $self = shift;

    my $sock = $self->socket->accept();
    my $request_data = $self->_read_request_from_socket($sock);
    my $rewritten = $self->_proxy_rewrite($request_data);
    my $server_sock = $self->_send_data_to_real_server($rewritten);

    my $response_data = $self->_read_request_from_socket($server_sock);
    my $rewritten_response_data = $self->proxy_rewrite($response_data);

    $sock->print($rewritten_response_data);

    my $http_request = HTTP::Request->parse($request_data);
    my $http_response = HTTP::Response->parse($response_data);
    return ($http_request, $http_response);
}

sub _proxy_rewrite_for_server {
    my($self, $data) = @_;

    $self->_proxt_rewrite($data, $self->url, $self->real_server_url);
}

sub _proxy_rewrite_for_client {
    my($self, $data) = @_;

    $self->_proxy_rewrite($data, $self->real_server_url, $self->url);
}

sub _proxy_rewrite {
    my($self, $data, $search, $replace) = @_;

    $data =~ s/\Q$search\E/$replace/g;
    return $data;
}

sub _send_data_to_real_server {
    my $self = shift;
    my $data = shift;

    my $peer = $self->real_server_url =~ m#http://(.*)/?#;
    my $sock = IO::Socket::INET->new(
                    PeerAddr => $peer,
                    Proto => 'tcp');

    $sock->print($data);
    return $sock;
}

sub _read_request_from_socket {
    my $self = shift;
    my $sock = shift;

    my $sel = IO::Select->new($sock);
    my $buf = '';
    while($sel->can_read) {
        my $count = $sock->sysread($buf, 1024, length($buf));
        unless ($count) {
            Carp::croak("Error reading from socket: $!");
        }
    }
    return $buf;
}


1;
