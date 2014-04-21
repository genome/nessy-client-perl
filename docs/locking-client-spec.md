# Client lock library requirements

## Standalone

The client library should be a stand-alone library, not part of the Genome
namesapce.  Genome::Sys::Lock::lock_resource() and unlock_resource() will
call this new library.

## Implementation

There are two main parts.

1. A keychain process to make requests on behalf of the main
    process.  It communicates with the main process over a
    pipe, and with the locking server over a TCP connection.
2. The main library that makes requests to the server via the
    keychain to lock and unlock resources

## API

Every response from the server that indicates failure will throw an exception in the
main process.

### my $manager = LockManager->new(%params)

Sets up an object to manage locking.  %params include:

* details of how to connect to the server as a URL
* Override for lock TTL (optional)
* Override for lock timeout (optional)
* API version (optional, defaults to "v1" for now)

Instantiating a LockManager will necessitate creating a keychain process.

### my $claim = $manager->claim(%params);

Claim a resource.  %params include:

* resource name (string, required)
* override for the lock timeout (optional)
* data: JSON-encoded string.  Ignored by the server (optional)
This data will be a hash that may include info like the originating hostname,
processID, LSF ID.

The in the keychain, the process for claiming a lock is:
1. send a POST request to http://server/v1/claims with params resource=*resourcename*
in the body.
2. Wait for response which will include a Location header specifying the
ID for this claim (claimid)
3. Start looping
    1. Send a PATCH request to http://server/v1/claims/*claimid*/ with these params
       in the body:
        * ttl=*ttl*
        * timeout=*timeout*
        * status=active
    2. IF the response is successful:
        * Add this claim to the shared list of outstanding claims
        * Wake up the watchdog thread so it can respond to an absurdly short TTL
        * return a Claim object to the caller
    3. If the response os 409 (Conflict) sleep for a bit and try patching again

### $claim->refresh(%params);

Used to refresh the TTL for a held lock.  The watchdog thread will normally
call this for us.

Sends a PUT request to http://server/v1/claims/*claimid*/ with these params
in the body
    * ttl=*ttl*
    * status=active

### DESTROY()

The destructor releases the claim by sending a PUT request to
http://server/v1/claims/*claimid*/ with the the param status=released
in the body.  When a successful response is received,
this claim is removed from the shared list of outstanding claims.

One complication here is that exceptions are automatically masked by the Perl
runtime during the destructor.  One solution is Exception::Guaranteed; it uses
threads and I don\'t understand how it works yet.  Another solution is for the
process to kill itself with SIGABRT or just call exit() if there are problems.

## Keychain

The Keychain process will be an event-driven program triggered by
    * Data from the main process
    * Data from the lock server
    * Timer for the next TTL event



## Genome Integration

Genome::Sys::Lock will need a package-level lexical to hold a hash of
outstanding claim objects, similar to the existing %SYMLINKS_TO_REMOVE,
and a singleton LockManger object.  The server connection details will
be stored in an env variable the same way the other GENOME_* vars are used.

lock_resource() will, in addition to it's current code, call ->claim() on
the resource, and add the Claim object to it's hash.  unlock_resource()
will remove it from the list.  exit_cleanup() will call ->release on all
the outstanding lock objects  and finally join() the watchdog thread.

