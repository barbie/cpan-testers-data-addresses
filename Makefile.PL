use 5.006; #due to 'warnings' pragma
use ExtUtils::MakeMaker;
WriteMakefile(
    'NAME'          => 'CPAN::Testers::Data::Addresses',
    'VERSION_FROM'  => 'lib/CPAN/Testers/Data/Addresses.pm',
    'PREREQ_PM'     => {

        'Class::Accessor::Fast'             => 0,
        'CPAN::Testers::Common::DBUtils'    => 0,
        'Config::IniFiles'                  => 0,
        'File::Basename'                    => 0,
        'File::Path'                        => 0,
        'File::Slurp'                       => 0,
        'Getopt::Long'                      => 0,
        'IO::File'                          => 0,

        'Test::More'                        => 0,       # only for testing

        'DBD::mysql'                        => 0,
        'DBD::SQLite'                       => 0,
    },

    'PL_FILES'      => {},
    'INSTALLDIRS'   => 'site',
    NO_META         => 1,

    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT	=> 'CPAN Testers Addresses Database Manager',
       AUTHOR	=> 'Barbie <barbie@cpan.org>') : ()),
);
