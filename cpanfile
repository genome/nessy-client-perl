requires 'AnyEvent', '5.33';
requires 'AnyEvent::HTTP', '2.15';
requires 'JSON';
requires 'LWP::UserAgent';
requires 'Sub::Install';
requires 'Sub::Name';

on 'test' => sub {
    requires 'Plack';
    requires 'Test::Exception';
    requires 'Test::MockObject';
};
