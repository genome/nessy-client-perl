package Nessy::Claim;

use strict;
use warnings;

use Nessy::Properties qw(resource_name on_release _is_released _pid _tid);

my $can_use_threads = eval 'use threads; 1';

sub new {
    my ($class, %params) = @_;
    my $self = $class->_verify_params(\%params, qw(resource_name on_release));

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
    return if $self->_is_released();
    $self->_is_released(1);

    $self->on_release->(@_);
}

sub DESTROY {
    my $self = shift;
    if (($self->_pid == $$) and ($self->_tid == $self->_get_tid)) {
        $self->release;
    }
}

1;
