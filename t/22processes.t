#!/usr/bin/perl -w
use strict;

use CPAN::Testers::Data::Addresses;
use Data::Dumper;
use File::Spec;
use File::Slurp;
use Test::More tests => 19;

my $config = File::Spec->catfile('t','_DBDIR','test-config.ini');
my $output = File::Spec->catfile('t','_DBDIR','output.txt');

## Test Data

my %results = (
    parsed_map => {
        'srezic@cpan.org' => {
            'testerid' => 2,
            'pause' => 'SREZIC',
            'match' => '# MAPPED ADDRESS',
            'name' => 'Slaven Rezi&#x0107;',
            'addressid' => 2
        },
        'bingos@cpan.org' => {
            'testerid' => 4,
            'pause' => 'BINGOS',
            'match' => '# MAPPED ADDRESS',
            'name' => 'Chris Williams',
            'addressid' => 4
        },
        'jj@jonallen.info ("JJ")' => {
            'testerid' => 3,
            'pause' => 'JONALLEN',
            'match' => '# MAPPED ADDRESS',
            'name' => 'Jon Allen',
            'addressid' => 3
        },
        'kriegjcb@mi.ruhr-uni-bochum.de ((Jost Krieger))' => {
            'testerid' => 1,
            'pause' => 'JOST',
            'match' => '# MAPPED ADDRESS',
            'name' => 'Jost Krieger',
            'addressid' => 1
        }
    },
    stored_map => {},
    pause_map => {
        'jost' => {
            'testerid' => 0,
            'pause' => 'JOST',
            'match' => '# PAUSE ID',
            'name' => 'Jost Krieger',
            'addressid' => 0
        },
        'barbie' => {
            'testerid' => 0,
            'pause' => 'BARBIE',
            'match' => '# PAUSE ID',
            'name' => 'Barbie',
            'addressid' => 0
        },
        'srezic' => {
            'testerid' => 0,
            'pause' => 'SREZIC',
            'match' => '# PAUSE ID',
            'name' => 'Slaven Rezic',
            'addressid' => 0
        },
        'jonallen' => {
            'testerid' => 3,
            'pause' => 'JONALLEN',
            'match' => '# PAUSE ID',
            'name' => 'Jon Allen',
            'addressid' => 3
        },
        'bingos' => {
            'testerid' => 0,
            'pause' => 'BINGOS',
            'match' => '# PAUSE ID',
            'name' => 'Chris Williams',
            'addressid' => 0
        }
    },
    cpan_map => {
        'jost.krieger+pppause@ruhr-uni-bochum.de' => {
            'testerid' => 0,
            'pause' => 'JOST',
            'match' => '# CPAN EMAIL',
            'name' => 'Jost Krieger',
            'addressid' => 0
        },
        'chris@bingosnet.co.uk' => {
            'testerid' => 0,
            'pause' => 'BINGOS',
            'match' => '# CPAN EMAIL',
            'name' => 'Chris Williams',
            'addressid' => 0
        },
        'slaven@rezic.de' => {
            'testerid' => 0,
            'pause' => 'SREZIC',
            'match' => '# CPAN EMAIL',
            'name' => 'Slaven Rezic',
            'addressid' => 0
        },
        'jj@jonallen.info' => {
            'testerid' => 3,
            'pause' => 'JONALLEN',
            'match' => '# CPAN EMAIL',
            'name' => 'Jon Allen',
            'addressid' => 3
        },
        'barbie@missbarbell.co.uk' => {
            'testerid' => 0,
            'pause' => 'BARBIE',
            'match' => '# CPAN EMAIL',
            'name' => 'Barbie',
            'addressid' => 0
        }
    },
    address_map => {
        'srezic@cpan.org' => {
            'testerid' => 2,
            'pause' => 'SREZIC',
            'match' => '# MAPPED EMAIL',
            'name' => 'Slaven Rezi&#x0107;',
            'addressid' => 2
        },
        'kriegjcb@mi.ruhr-uni-bochum.de' => {
            'testerid' => 1,
            'pause' => 'JOST',
            'match' => '# MAPPED EMAIL',
            'name' => 'Jost Krieger',
            'addressid' => 1
        },
        'bingos@cpan.org' => {
            'testerid' => 4,
            'pause' => 'BINGOS',
            'match' => '# MAPPED EMAIL',
            'name' => 'Chris Williams',
            'addressid' => 4
        },
        'jj@jonallen.info' => {
            'testerid' => 3,
            'pause' => 'JONALLEN',
            'match' => '# MAPPED EMAIL',
            'name' => 'Jon Allen',
            'addressid' => 3
        }
    },
    unparsed_map => {
        'andreas.koenig.gmwojprw@franz.ak.mind.de' => {
            'email' => 'andreas.koenig.gmwojprw@franz.ak.mind.de',
            'testerid' => 0,
            'sort' => '',
            'addressid' => 0
        },
        '"Josts Smokehouse" <JOST@cpan.org>' => {
            'email' => 'JOST@cpan.org',
            'testerid' => 0,
            'sort' => '',
            'addressid' => 0
        },
        'imacat@mail.imacat.idv.tw' => {
            'email' => 'imacat@mail.imacat.idv.tw',
            'testerid' => 0,
            'sort' => '',
            'addressid' => 0
        },
        'stro@cpan.org' => {
            'email' => 'stro@cpan.org',
            'testerid' => 0,
            'sort' => '',
            'addressid' => 0
        },
        'CPAN.DCOLLINS@comcast.net' => {
            'email' => 'CPAN.DCOLLINS@comcast.net',
            'testerid' => 0,
            'sort' => '',
            'addressid' => 0
        },
        '"Oliver Paukstadt" <cpan@sourcentral.org>' => {
            'email' => 'cpan@sourcentral.org',
            'testerid' => 0,
            'sort' => '',
            'addressid' => 0
        },
        'Ulrich Habel <rhaen@cpan.org>' => {
            'email' => 'rhaen@cpan.org',
            'testerid' => 0,
            'sort' => '',
            'addressid' => 0
        }
    },
);


SKIP: {
    skip "Unable to locate config file [$config]", 19   unless(-f $config);

    ### Prepare object
    my $obj;
    unlink($output)  if(-f $output);
    ok( $obj = CPAN::Testers::Data::Addresses->new(config => $config, output => $output), "got object" );

    ### Test Underlying Process Methods

    $obj->load_addresses;
    is_deeply( $obj->{$_}, $results{$_}, ".. load - $_") for(qw(parsed_map stored_map pause_map cpan_map address_map unparsed_map));
    #diag("$_:" . Dumper($obj->{$_}))    for(qw(parsed_map stored_map pause_map cpan_map address_map unparsed_map));
    #diag("$_:" . Dumper($obj->{$_}))    for(qw(unparsed_map));

    $obj->match_addresses;
    is_deeply( $obj->{result}{NOEMAIL}, undef, '.. load - NOEMAIL');

    $obj->print_addresses;
    $obj = undef;

    my $text = read_file($output);
    unlike($text, qr/ERRORS:/, '.. found no errors');
    like($text, qr/MATCH:/,    '.. found matches');
    like($text, qr/PATTERNS:/, '.. found patterns');

    ### Test Direct Process Methods

    # test update process
    my $f = 't/_DBDIR/update.txt';
    write_file($f,'0,0,barbie@missbarbell.co.uk,Barbie,BARBIE');
    $obj = CPAN::Testers::Data::Addresses->new(config => $config, update => $f);

    my $dbh = $obj->dbh;
    my @ct1 = $dbh->get_query('array','select count(*) from tester_profile');
    $obj->process;
    my @ct2 = $dbh->get_query('array','select count(*) from tester_profile');
    is($ct2[0]->[0] - $ct1[0]->[0], 1, '.. 1 address added');

    # test search process
    unlink($output)  if(-f $output);
    ok( $obj = CPAN::Testers::Data::Addresses->new(config => $config, output => $output), "got object" );
    $dbh = $obj->dbh;
    $obj->process;
    $obj = undef;

    $text = read_file($output);
    unlike($text, qr/ERRORS:/, '.. found no errors');
    like($text, qr/MATCH:/,    '.. found matches');
    like($text, qr/PATTERNS:/, '.. found patterns');

    # test reindex
    ok( $obj = CPAN::Testers::Data::Addresses->new(config => $config, reindex => 1), "got object" );
    is( $obj->_lastid, 0, "before reindex" );
    $obj->process;
    is( $obj->_lastid, 2975969, "after reindex" );


    #TODO:
    #$obj = CPAN::Testers::Data::Addresses->new(config => 't/test-config.ini', backup => 1);
}
