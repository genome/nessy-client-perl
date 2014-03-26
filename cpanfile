requires 'AnyEvent', '5.33';
requires 'AnyEvent::HTTP', '2.15';

on 'test' => sub {
    requires 'Plack';
};
