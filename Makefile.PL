use strict;
use warnings;

use ExtUtils::MakeMaker 6.30;

my %WriteMakefileArgs = (
    BUILD_REQUIRES => {
        'Test::More' => 0,
        'POSIX' => 0,
        'Sys::Hostname' => 0,
        'Time::HiRes' => 0
    },
    CONFIGURE_REQUIRES => {
        "ExtUtils::MakeMaker" => "6.30"
    },
    DISTNAME => 'Nessy-Client',
    EXE_FILES => [],
    LICENSE => 'perl',
    NAME => 'Nessy::Client',
    PREREQ_PM => {
        'Carp' => 0,
        'Socket' => 0,
        'IO::Socket' => 0,
        'JSON' => 0,
        'AnyEvent' => 5.33,
        'AnyEvent::Handle' => 0,
        'AnyEvent::HTTP' => 2.15,
        'Scalar::Util' => 0,
        'Sub::Install' => 0,
        'Sub::Name' => 0,
        'Data::Dumper' => 0,
        'Getopt::Long' => 0,
        'File::Basename' => 0,
        'Fcntl' => 0,
    },
    VERSION => '0.001',
    test => {
        TEST => "t/*.t",
    },
);

unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}
 
delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };
 
WriteMakefile(%WriteMakefileArgs);
