use GSCLockClient;

use Test::More;

my $server = GSCLockClient::FakeServer();

my $manager = GSCLockClient->new($server);

sub test_get_release {
    is_deeply($manager->claim_names(), [], 'Manager says we have no locks');

    my $lock = $manager->claim('foo');
    ok($lock, 'Got lock foo');
    is($lock->state, 'active', 'lock is active');
    is_deeply($manager->claim_names(), ['foo'], 'Manager says we have lock foo');

    ok($lock->release, 'Release lock');
    is($lock->state, 'released', 'Lock is released');

    is_deeply($manager->claim_names(), [], 'All locks released');
}

sub test_get_undef {
    is_deeply($manager->claim_names(), [], 'All locks released');
    my $lock = $manager->claim('foo');

    ok($lock, 'Get lock foo');
    is($lock->state, 'active', 'lock is active');
    undef($lock);
    
    is_deeply($manager->claim_names(), [], 'All locks released');
}

