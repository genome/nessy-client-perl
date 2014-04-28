use strict;
use warnings FATAL => 'all';

use Test::More;
use Test::MockObject;

use AnyEvent;

unless ($ENV{NESSY_SERVER_URL}) {
    plan skip_all => 'Needs nessy-server for testing; '
        .' set NESSY_SERVER_URL to something like http://127.0.0.1:5000';
}


use_ok('Nessy::Daemon::CommandInterface');


subtest test_create_timer => sub {
    my $eg = _mock_event_generator();
    my $ci = _create_command_interface($eg);

    _run_in_event_loop(0.5, sub {
        $ci->create_timer(seconds => 0.1);
    });

    $eg->called_ok('timer_callback', 'timer callback called');
};


subtest test_delete_timer => sub {
    my $eg = _mock_event_generator();
    my $ci = _create_command_interface($eg);

    _run_in_event_loop(0.5, sub {
        $ci->create_timer(seconds => 0.1);
        $ci->delete_timer();
    });

    ok(!defined($eg->next_call), 'timer callback not called');
};


done_testing();


sub _run_in_event_loop {
    my ($duration, $coderef) = @_;

    my $cv = AnyEvent->condvar;
    my $death_timer = AnyEvent->timer(after => $duration, cb => $cv);

    $coderef->();

    $cv->recv;
}

sub _mock_event_generator {
    my $eg = Test::MockObject->new;
    $eg->set_true('timer_callback');

    return $eg;
}

sub _create_command_interface {
    my $eg = shift;

    Nessy::Daemon::CommandInterface->new(event_generator => $eg,
        resource => _get_resource());
}

sub rndStr{ join'', @_[ map{ rand @_ } 1 .. shift ] }
sub _get_resource {
    return rndStr 20, 'A'..'Z', 'a'..'z', 0..9, '-', '_', '.';
};
