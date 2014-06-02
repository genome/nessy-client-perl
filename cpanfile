requires 'AnyEvent', '5.33';
requires 'AnyEvent::HTTP', '2.15';
requires 'AnyEvent::Handle';
requires 'Carp';
requires 'Data::Dumper';
requires 'Data::UUID';
requires 'Fcntl';
requires 'File::Basename';
requires 'Getopt::Long';
requires 'IO::Socket';
requires 'JSON';
requires 'Scalar::Util';
requires 'Socket';
requires 'Sub::Install';
requires 'Sub::Name';

on build => sub {
    requires 'POSIX';
    requires 'Sys::Hostname';
    requires 'Test::More';
    requires 'Time::HiRes';
};

on develop => sub {
    requires 'CPAN::Uploader';
    requires 'Minilla', '1.1.0';
    requires 'Version::Next';
};

on test => sub {
    requires 'Plack';
    requires 'Test::Exception';
    requires 'Test::MockObject';
};
