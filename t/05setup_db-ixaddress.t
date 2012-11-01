#!/usr/bin/perl -w
use strict;

use Test::More tests => 2;
use DBI;
use File::Spec;
use File::Path;
use File::Basename;

my $f = File::Spec->catfile('t','_DBDIR','test.db');
#unlink $f if -f $f;
mkpath( dirname($f) );

my @sql = (
        'CREATE TABLE ixaddress (
            id          int NOT NULL,
            addressid   int NOT NULL,
          PRIMARY KEY  (id)
        )',

        'CREATE TABLE tester_address (
            addressid   int NOT NULL,
            testerid    int NOT NULL default 0,
            address     text NOT NULL,
            email	    text default NULL,
          PRIMARY KEY  (addressid)
        )',

        'CREATE TABLE tester_profile (
            testerid    int NOT NULL,
            name	    text default NULL,
            pause	    text default NULL,
          PRIMARY KEY  (testerid)
        )',
);

my $dbh = DBI->connect("dbi:SQLite:dbname=$f", '', '', {AutoCommit=>1});
$dbh->do($_)    for(@sql);

while(<DATA>){
  chomp;
  my ($addressid,$address,$email,$testerid,$name,$pause) = split(',');
  $dbh->do('INSERT INTO tester_address ( addressid, testerid, address, email ) VALUES ( ?, ?, ?, ? )', {}, $addressid,$testerid,$address,$email );
  $dbh->do('INSERT INTO tester_profile ( testerid, name, pause ) VALUES ( ?, ?, ? )', {}, $testerid,$name,$pause );
}

my ($ct1) = $dbh->selectrow_array('select count(*) from tester_address');
my ($ct2) = $dbh->selectrow_array('select count(*) from tester_profile');

$dbh->disconnect;

is($ct1, 4, "row count - address");
is($ct2, 4, "row count - profile");


__DATA__
1|kriegjcb@mi.ruhr-uni-bochum.de ((Jost Krieger))|kriegjcb@mi.ruhr-uni-bochum.de,1,Jost Krieger,JOST
2|srezic@cpan.org|srezic@cpan.org,2,Slaven Rezi&#x0107;,SREZIC
3|jj@jonallen.info ("JJ")|jj@jonallen.info,3,Jon Allen,JONALLEN
4|bingos@cpan.org|bingos@cpan.org,4,Chris Williams,BINGOS
