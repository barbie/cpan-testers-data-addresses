#!/usr/bin/perl -w
use strict;

use Test::More tests => 10;
use Test::Trap;

{
    use CPAN::Testers::Data::Addresses;

    my $VERSION = '0.14';

    my $obj;
    my $stdout;
    my $config = 't/20attributes.ini';

    {
        trap { $obj = CPAN::Testers::Data::Addresses->new() };

        like($trap->stdout,qr/Must specify the configuration file/,'.. no file name');
        like($trap->stdout,qr/Usage:.*--config|c=<file>/,'.. got help');
    }

    {
        trap { $obj = CPAN::Testers::Data::Addresses->new( config => 'bogus.file' ) };

        like($trap->stdout,qr/Configuration file .*? not found/,'.. no file found');
        like($trap->stdout,qr/Usage:.*--config|c=<file>/,'.. got help');
    }

    {
        trap { $obj = CPAN::Testers::Data::Addresses->new( config =>  $config, help => 1 ) };

        like($trap->stdout,qr/Usage:.*--config|c=<file>/,'.. got help');
        like($trap->stdout,qr/$0 v$VERSION/,'.. got version');
    }

    {
        trap { $obj = CPAN::Testers::Data::Addresses->new( config => $config, version => 1 ) };

        unlike($trap->stdout,qr/Usage:.*--config|c=<file>/,'.. no help');
        like($trap->stdout,qr/$0 v$VERSION/,'.. got version');
    }

    {
        unshift @ARGV, '--help';
        trap { $obj = CPAN::Testers::Data::Addresses->new( config =>  $config ) };

        like($trap->stdout,qr/Usage:.*--config|c=<file>/,'.. got help');
        like($trap->stdout,qr/$0 v$VERSION/,'.. got version');
    }
}
