package GSCLockClient::Keychain::Daemon::Claim;

use GSCLockClient::Properties qw(resource_name state claim_id base_url keychain ttl_timer_watcher);

use AnyEvent;
use AnyEvent::HTTP;
use JSON;
use Data::Dumper;

use constant STATE_NEW          => 'new';
use constant STATE_REGISTERING  => 'registering';
use constant STATE_WAITING      => 'waiting';
use constant STATE_ACTIVATING   => 'activating';
use constant STATE_ACTIVE       => 'active';
use constant STATE_RENEWING     => 'renewing';
use constant STATE_RELEASED     => 'released';
use constant STATE_RELEASING    => 'releasing';
use constant STATE_FAILED       => 'failed';

my %STATE = (
    STATE_NEW()         => [ STATE_REGISTERING ],
    STATE_REGISTERING() => [ STATE_WAITING, STATE_ACTIVE ],
    STATE_WAITING()     => [ STATE_ACTIVATING ],
    STATE_ACTIVATING()  => [ STATE_ACTIVE, STATE_WAITING ],
    STATE_ACTIVE()      => [ STATE_RENEWING, STATE_RELEASING ],
    STATE_RELEASING()   => [ STATE_RELEASED ],
    STATE_RENEWING()    => [ STATE_ACTIVE ],
    STATE_FAILED()      => [],
    STATE_RELEASED()    => [],
);


my $json_parser = JSON->new();
sub new {
    my($class, %params) = @_;

    my $self = bless {}, $class;
    $self->url($params{url}) || die "'url' is required";
    $self->resource_name($params{resource_name}) || die "'resource_name' is required";
    $self->keychain($params{keychain}) || die "'keychain' is required";
    $self->state(STATE_NEW);

    $self->send_register();
    return $self;
}

sub release {

}

sub transition {
    my($self, $new_state) = @_;

    my @allowed_next = @{ $STATE{ $self->state } };
    foreach my $allowed_next ( @allowed_next ) {
        if ($allowed_next eq $new_state) {
            $self->state($new_state);
            return 1;
        }
    }
    $self->_failure("Illegal transition from ".$self->state." to $new_state");
}

sub _failure {
    my($self, $error) = @_;

    my $message = { resource_name => $self->resource_name };
    $error && ($message->{error_message} = $error);

    $self->keychain->claim_failed($message);
}

sub _success {
    my $self = shift;

    $self->keychain->claim_succeeded({ resource_name => $self->resource_name });
}

sub send_register {
    my $self = shift;

    AnyEvent::HTTP::http_post(
        $self->url . '/claims',
        $json_parser->encode({ resource => $self->resource_name }),
        'Content-Type' => 'application/json',
        sub { $self->recv_register_response() }
    );
    $self->transition(STATE_REGISTERING);
}

sub recv_register_response {
    my $self = shift;
    my($body, $headers) = @_;

    my $status = $headers->{Status};
    if ($status == 201) {
        $self->state_active();

    } elsif ($status == 202) {
        $self->state_waiting();

    } elsif ($status == 400) {
        $self->state_fail();

    } else {
        $self->_failure("Unexpected response status $status in recv_register_response.\n"
            . "Headers: " . Data::Dumper::Dumper($headers) ."\n"
            . "Body: " . Data::Dumper::Dumper($body)
        );
    }
}

sub state_active {
    my $self = shift;
    $self->transition(STATE_ACTIVE);

    my $ttl = $self->_ttl_timer_value;
    my $w = AnyEvent->timer(
                after => $ttl,
                interval => $ttl,
                cb => sub { $self->send_renewal() }
            );
    $self->ttl_timer_watcher($w);

    $self->_success();
}

sub _ttl_timer_value {
    my $self = shift;
    return $self->ttl / 4;
}

sub state_fail {
    my $self = shift;
    $self->state(STATE_FAIL);
    $self->keychain->claim_failed( { resource_name => $self->resource_name });
}




1;
