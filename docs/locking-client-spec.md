# Client lock library requirements

## Claim State Machine

Each claim will have an instance of the below state machine associated with it.
There must be only one claim (therefore one state machine) per resource.


Complete state table:

State             | Description                                      | Associated Data
----------------- | ------------------------------------------------ | -------------------------------------
new               | initial state                                    | timeout timer
Aborting          | waiting for response to PATCH (status=aborted)   | abort PATCH request
Activating        | waiting for response to PATCH (status=active)    | activate PATCH request, timeout timer
Registering       | waiting for response to POST                     | register POST request, timeout timer
Releasing         | waiting for response to PATCH (status=released)  | release PATCH request
Renewing          | waiting for response to PATCH (ttl=...)          | renew PATCH request
Withdrawing       | waiting for response to PATCH (status=withdrawn) | withdraw PATCH request
active            | waiting to send next heartbeat                   | renew timer
done              | final state, an un-actionable event has occurred | -
fail              | final state, an error has occurred               | -
retrying abort    | abort PATCH request failed, waiting to retry     | retry abort timer
retrying activate | activate PATCH request failed, waiting to retry  | retry activate timer, timeout timer
retrying register | register POST request failed, waiting to retry   | retry register timer, timeout timer
retrying release  | release PATCH request failed, waiting to retry   | retry release timer
retrying renew    | renew PATCH request failed, waiting to retry     | retry renew timer
retrying withdraw | withdraw PATCH request failed, waiting to retry  | retry withdraw timer
waiting           | waiting until next activate attempt              | activate timer, timeout timer


Complete transition table:

Source            | Destination        | Condition                 | Actions
----------------- | ------------------ | ------------------------- | ----------------------------------------------------
new               | Registering        | -                         | send POST, create timeout timer
Aborting          | aborted            | response (204)            | -
Aborting          | done               | signal received           | -
Aborting          | done               | timeout timer triggers    | -
Aborting          | fail               | response (4xx)            | terminate client
Aborting          | retrying abort     | response (5xx)            | create retry timer
Activating        | Aborted            | signal received           | send PATCH (status=aborted)
Activating        | Withdrawing        | timeout timer triggers    | send PATCH (status=withdrawn)
Activating        | active             | response (200)            | create renew timer, delete timeout timer, notify client lock is acquired
Activating        | fail               | response (4xx)            | terminate client
Activating        | retrying activate  | response (5xx)            | create retry timer
Activating        | waiting            | response (409)            | create activate timer
Registering       | done               | signal received           | delete timeout timer
Registering       | done               | timeout timer triggers    | notify client of timeout
Registering       | fail               | response (4xx except 404) | terminate client
Registering       | retrying register  | response (5xx, 404)       | create retry timer
Registering       | waiting            | response (201)            | create renew timer
Registering       | waiting            | response (202)            | create activate timer
Releasing         | done               | signal received           | -
Releasing         | done               | timeout timer triggers    | -
Releasing         | fail               | response (4xx)            | terminate client
Releasing         | released           | response (204)            | notify client lock is released
Releasing         | retrying release   | response (5xx)            | create retry timer
Renewing          | Aborting           | signal received           | send PATCH (status=aborted)
Renewing          | Releasing          | client requests release   | send PATCH (status=released)
Renewing          | active             | response (200)            | create renew timer
Renewing          | fail               | response (4xx)            | terminate client
Renewing          | retrying renew     | response (5xx)            | create retry timer
Withdrawing       | done               | signal received           | -
Withdrawing       | done               | timeout timer triggers    | -
Withdrawing       | fail               | response (4xx)            | terminate client
Withdrawing       | retrying withdraw  | response (5xx)            | create retry timer
Withdrawing       | withdrawn          | response (204)            | -
active            | Aborting           | signal received           | send PATCH (status=aborted), delete renew timer
active            | Releasing          | client requests release   | send PATCH (status=released), delete renew timer
active            | Renewing           | renew timer triggers      | send PATCH (ttl=...)
retrying abort    | Aborting           | retry timer triggers      | send PATCH (status=aborted)
retrying abort    | done               | signal received           | -
retrying abort    | done               | timeout timer triggers    | -
retrying activate | Aborting           | signal received           | send PATCH (status=aborted), delete retry timer
retrying activate | Activating         | retry timer triggers      | send PATCH (status=active)
retrying activate | Withdrawing        | timeout timer triggers    | send PATCH (status=withdrawn), delete retry timer
retrying register | Registering        | retry timer triggers      | send POST
retrying register | done               | signal received           | delete timeout timer
retrying register | done               | timeout timer triggers    | notify client of timeout
retrying release  | Releasing          | retry timer triggers      | send PATCH (status=released)
retrying release  | done               | signal received           | -
retrying release  | done               | timeout timer triggers    | -
retrying renew    | Aborting           | signal received           | send PATCH (status=aborted), delete retry timer
retrying renew    | Releasing          | client requests release   | send PATCH (status=released), delete retry timer
retrying renew    | Renewing           | retry timer triggers      | send PATCH (ttl=...)
retrying withdraw | Withdrawing        | retry timer triggers      | send PATCH (status=withdrawn)
retrying withdraw | done               | signal received           | -
retrying withdraw | done               | timeout timer triggers    | -
waiting           | Aborting           | signal received           | send PATCH (status=aborted), delete activate timer
waiting           | Activating         | activate timer triggers   | send PATCH (status=active)
waiting           | Withdrawing        | timeout timer triggers    | send PATCH (status=withdrawn), delete activate timer


Parameters used during by transitions:

- ttl
- resource
- user data
- timeout
- retry params (these are not necessarily the same)
    - abort - retrying abort should happen quickly, because we are failing
    - activate
    - withdraw
    - register
    - release
    - renew
- renew period
- activate params (might include backoff)


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

