package Nessy::Claim;

use strict;
use warnings;

use Nessy::Properties qw(resource_name on_release _is_released _pid _tid on_validate);

my $can_use_threads = eval 'use threads; 1';

sub new {
    my ($class, %params) = @_;
    my $self = $class->_verify_params(\%params, qw(resource_name on_release on_validate));

    bless $self, $class;

    $self->_pid($$);
    $self->_tid($self->_get_tid);

    return $self;
}

sub _get_tid {
    return $can_use_threads
        ? threads->tid
        : 0;
}

sub release {
    my $self = shift;
    return 1 if $self->_is_released();
    $self->_is_released(1);

    $self->on_release->(@_);
}

sub validate {
    my $self = shift;
    $self->on_validate->(@_);
}

sub DESTROY {
    my $self = shift;
    if (($self->_pid == $$) and ($self->_tid == $self->_get_tid)) {
        if (!defined($self->release())) {
            die "Failed to release claim for resource '"
                . $self->resource_name . "'";
        }
    }
}

1;

=pod

=head1 NAME

Nessy::Claim - Represent a claim on a resource

=head1 SYNOPSIS

  use Nessy::Client;

  my $client = Nessy::Client->new( url => $server_url );

  my $claim = $client->claim( $resource_name );

  do_something_while_resource_is_locked();

  $claim->release();

=head1 Constructor

Nessy::Claim instances should not be created by calling new() directly on this
class.  They should instead be instantiated by calling claim() on a
L<Nessy::Client> instance.

=head2 Methods

=over 4

=item resource_name()

Returns the resource name of this claim.  Set at the time the Nessy::Claim is
instantiated.

=item release()

Release the claim.  Returns true if the claim was successfully released,
meaning that the claim was valid at the time of release and the server
responded successfully when the release was requested.

A release might fail if the claim's ttl has expired (due to the inability to
contant the server to update the tll), or if the claim was removed on the
server by an administrator, for example.

C<release()> accepts an optional function ref as an argument used as a callback
to deliver the result to.  The callback an only be run if the main program
enters the AnyEvent event loop.

=item validate()

Validate the claim.  Returns true of the claim is still valid, false
otherwise.

C<validate()> accepts an optional function ref as an argument used as a callback
to deliver the result to.  The callback an only be run if the main program
enters the AnyEvent event loop.

=item DESTROY

Releases the claim when the instance goes out of scope; not called directly.

=back

=head1 SEE ALSO

L<Nessy::Client>, L<Nessy::Daemon>

=head1 LICENCE AND COPYRIGHT

Copyright (C) 2014 Washington University in St. Louis, MO.

This sofware is licensed under the same terms as Perl itself.
See the LICENSE file in this distribution.

=cut

