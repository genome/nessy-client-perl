use HTTP::Server::PSGI;

package HTTP::Server::PSGI;

# Modified to support psgix.harakiri.commit

no warnings 'redefine';
sub accept_loop {
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

1;
