#!perl

use strict;
use warnings;

use Test::More tests => 23;
use File::Path;

use CPAN::Testers::Data::Addresses;

my $logfile = 't/50logging.log';

unlink($logfile) if(-f $logfile);

{
    ok( my $obj = CPAN::Testers::Data::Addresses->new(config => 't/50logging.ini'), "got object" );

    is($obj->logfile, $logfile, 'logfile default set');
    is($obj->logclean, 0, 'logclean default set');

    $obj->_log("Hello");
    $obj->_log("Goodbye");

    ok( -f $logfile, '50logging.log created in current dir' );

    my @log = do { open FILE, '<', $logfile; <FILE> };
    chomp @log;

    is(scalar(@log),2, 'log written');
    like($log[0], qr!\d{4}/\d\d/\d\d \d\d:\d\d:\d\d Hello!,      'line 2 of log');
    like($log[1], qr!\d{4}/\d\d/\d\d \d\d:\d\d:\d\d Goodbye!,    'line 3 of log');
}


{
    ok( my $obj = CPAN::Testers::Data::Addresses->new(config => 't/50logging.ini'), "got object" );

    is($obj->logfile, $logfile, 'logfile default set');
    is($obj->logclean, 0, 'logclean default set');

    $obj->_log("Back Again");

    ok( -f $logfile, '50logging.log created in current dir' );

    my @log = do { open FILE, '<', $logfile; <FILE> };
    chomp @log;

    is(scalar(@log),3, 'log written');
    like($log[0], qr!\d{4}/\d\d/\d\d \d\d:\d\d:\d\d Hello!,      'line 2 of log');
    like($log[1], qr!\d{4}/\d\d/\d\d \d\d:\d\d:\d\d Goodbye!,    'line 3 of log');
    like($log[2], qr!\d{4}/\d\d/\d\d \d\d:\d\d:\d\d Back Again!, 'line 5 of log');
}

{
    ok( my $obj = CPAN::Testers::Data::Addresses->new(config => 't/50logging.ini'), "got object" );

    is($obj->logfile, $logfile, 'logfile default set');
    is($obj->logclean, 0, 'logclean default set');
    $obj->logclean(1);
    is($obj->logclean, 1, 'logclean reset');

    $obj->_log("Start Again");

    ok( -f $logfile, '50logging.log created in current dir' );

    my @log = do { open FILE, '<', $logfile; <FILE> };
    chomp @log;

    is(scalar(@log),1, 'log written');
    like($log[0], qr!\d{4}/\d\d/\d\d \d\d:\d\d:\d\d Start Again!, 'line 1 of log');
}

ok( unlink($logfile), 'removed 50logging.log' );
