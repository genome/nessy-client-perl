[![Build Status](https://travis-ci.org/genome/nessy-client-perl.png?branch=master)](https://travis-ci.org/genome/nessy-client-perl)
# NAME

Nessy::Client - Client API for the Nessy lock server

# SYNOPSIS

    use Nessy::Client;

    my $client = Nessy::Client->new( url => 'http://nessy.server.example.org/' );

    my $claim = $client->claim( "my resource" );

    do_something_while_resource_is_locked();

    $claim->release();

# Constructor

    my $client = Nessy::Client->new( url => $url,
                                     default_ttl => $ttl_seconds,
                                     default_timeout => $timeout_seconds,
                                     api_version => $version_string );

Create a new connection to the Nessy locking server.  `url` is the top-level
URL the Nessy locking server is listening on.  `default_ttl` is the default
time-to-live for all claims created through this client instance.
`default_timeout` is the default command timeout for claims.  `api_version`
is the dialect to use when talking to the server.

`url` is the only required argument.  `default_ttl` will default to 60
seconds.  `default_timeout` will default to `undef`, meaning that commands
will block for as long as necessary.  `api_version` will default to "v1".

When a client instance is created, it will fork/exec a process
([Nessy::Daemon](https://metacpan.org/pod/Nessy::Daemon)) that manages claims for the creating process.

# Methods

- api\_version()
- api\_version($new\_version)

    Get or set the api\_version.  Changing this attribute does not affect any
    claims already created.

- default\_ttl
- default\_ttl( $new\_default\_ttl\_seconds )

    Get or the set the detault\_ttl.  Changing this attribute does not affect any
    claims already created.

- default\_timeout
- default\_timeout( $new\_timeout\_seconds )

    Get or the set the default\_timeout.  Changing this attribute does not affect any
    claims already created.

- claim()

        my $claim = $client->claim( $resource_name, %params);

    Attempt to lock a named resource.  `$resource_name` is a plain string.
    `%params` is an optional list of key/value pairs.  The default behavior is
    for claim() to block until the named resource has been successfully claimed.
    It returns an instance of [Nessy::Claim](https://metacpan.org/pod/Nessy::Claim) on success, and a false value on
    failure, such as if the command timeout expires before the claim is locked.

    Optional params are:

    - ttl

        Time-to-live for this claim.  Overrides the client's default\_ttl.  When a
        claim is made, it is valid on the server for this many seconds.  A claim's
        ttl is refreshed periodicly by the Daemon process, and so can persist for
        longer than the ttl.

    - timeout

        Command timeout for this claim.  Overrides the client's default\_ttl.

    - user\_data

        User data attached to this claim.  The server does not use it at all.
        This data may be a reference to a deep data structure.  It must be serializable
        with the JSON module.

    - cb

        Normally claim() is a blocking function.  If cb is a function ref, then
        claim() returns immediately.  When the claim is finalized as successful or not,
        this function is called with the result as the only argument.  In order for
        this asynchronous call to proceed, the main program must enter the AnyEvent
        event loop.

- ping()

        my $worked = $client->ping()

        $client->ping( $result_coderef );

    Returns true if the Daemon process is alive, false otherwise.  ping
    accepts an optional callback coderef.  As with the claim() method, this
    callback can only run if the main process enters the AnyEvent loop.

- shutdown()

        $client->shutdown()

    Shuts down the Daemon process.  Any claims still being held will be
    abandoned.  The Daemon process will exit on its own if the parent
    process terminates.

# SEE ALSO

[Nessy::Claim](https://metacpan.org/pod/Nessy::Claim), [Nessy::Daemon](https://metacpan.org/pod/Nessy::Daemon)

# LICENSE

Copyright (C) The Genome Institute at Washington University in St. Louis.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Anthony Brummett <brummett@cpan.org>
