#!/usr/bin/perl -w
use strict;

use Test::More tests => 11;
use CPAN::Testers::Data::Addresses;
use File::Slurp;
use Data::Dumper;

## Test Data

my %results = (
    parsed_map => {
        '4' => {
            'testerid' => 'BINGOS',
            'pause' => undef,
            'match' => '# MAPPED ADDRESS',
            'name' => undef,
            'addressid' => '4|bingos@cpan.org|bingos@cpan.org'
            },
        '1' => {
            'testerid' => 'JOST',
            'pause' => undef,
            'match' => '# MAPPED ADDRESS',
            'name' => undef,
            'addressid' => '1|kriegjcb@mi.ruhr-uni-bochum.de ((Jost Krieger))|kriegjcb@mi.ruhr-uni-bochum.de'
        },
        '3' => {
            'testerid' => 'JONALLEN',
            'pause' => undef,
            'match' => '# MAPPED ADDRESS',
            'name' => undef,
            'addressid' => '3|jj@jonallen.info ("JJ")|jj@jonallen.info'
        },
        '2' => {
            'testerid' => 'SREZIC',
            'pause' => undef,
            'match' => '# MAPPED ADDRESS',
            'name' => undef,
            'addressid' => '2|srezic@cpan.org|srezic@cpan.org'
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
            'testerid' => 0,
            'pause' => 'JONALLEN',
            'match' => '# PAUSE ID',
            'name' => 'Jon Allen',
            'addressid' => 0
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
            'testerid' => 0,
            'pause' => 'JONALLEN',
            'match' => '# CPAN EMAIL',
            'name' => 'Jon Allen',
            'addressid' => 0
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
        'Jost Krieger' => {
            'testerid' => 'JOST',
            'pause' => undef,
            'match' => '# MAPPED EMAIL',
            'name' => undef,
            'addressid' => '1|kriegjcb@mi.ruhr-uni-bochum.de ((Jost Krieger))|kriegjcb@mi.ruhr-uni-bochum.de'
        },
        'Chris Williams' => {
            'testerid' => 'BINGOS',
            'pause' => undef,
            'match' => '# MAPPED EMAIL',
            'name' => undef,
            'addressid' => '4|bingos@cpan.org|bingos@cpan.org'
        },
        'Slaven Rezi&#x0107;' => {
            'testerid' => 'SREZIC',
            'pause' => undef,
            'match' => '# MAPPED EMAIL',
            'name' => undef,
            'addressid' => '2|srezic@cpan.org|srezic@cpan.org'
        },
        'Jon Allen' => {
            'testerid' => 'JONALLEN',
            'pause' => undef,
            'match' => '# MAPPED EMAIL',
            'name' => undef,
            'addressid' => '3|jj@jonallen.info ("JJ")|jj@jonallen.info'
        }
    },
    unparsed_map => {
        'andreas.koenig.gmwojprw@franz.ak.mind.de' => {
            'email' => 'andreas.koenig.gmwojprw@franz.ak.mind.de',
            'testerid' => 0,
            'sort' => '',
            'addressid' => 0
        },
        'cpan@sourcentral.org ("Oliver Paukstadt")' => {
            'email' => 'cpan@sourcentral.org',
            'testerid' => 0,
            'sort' => '',
            'addressid' => 0
        },
        'srezic@cpan.org' => {
            'email' => 'srezic@cpan.org',
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
        'bingos@cpan.org' => {
            'email' => 'bingos@cpan.org',
            'testerid' => 0,
            'sort' => '',
            'addressid' => 0
        },
        'rhaen@cpan.org (Ulrich Habel)' => {
            'email' => 'rhaen@cpan.org',
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
        'jj@jonallen.info ("JJ")' => {
            'email' => 'jj@jonallen.info',
            'testerid' => 0,
            'sort' => '',
            'addressid' => 0
        },
        'JOST@cpan.org ("Josts Smokehouse")' => {
            'email' => 'JOST@cpan.org',
            'testerid' => 0,
            'sort' => '',
            'addressid' => 0
        },
        'kriegjcb@mi.ruhr-uni-bochum.de ((Jost Krieger))' => {
            'email' => 'kriegjcb@mi.ruhr-uni-bochum.de',
            'testerid' => 0,
            'sort' => '',
            'addressid' => 0
        }
    },
);


### Prepare object

my $f = 't/_DBDIR/output.txt';
unlink($f)  if(-f $f);

ok( my $obj = CPAN::Testers::Data::Addresses->new(config => 't/test-config.ini', output => $f), "got object" );

### Test Underlying Process Methods

$obj->load_addresses;
is_deeply( $obj->{$_}, $results{$_}, ".. load - $_") for(qw(parsed_map stored_map pause_map cpan_map address_map unparsed_map));
#diag("$_:" . Dumper($obj->{$_}))    for(qw(parsed_map stored_map pause_map cpan_map address_map unparsed_map));

$obj->match_addresses;
is_deeply( $obj->{result}{NOEMAIL}, undef, '.. load - NOEMAIL');

$obj->print_addresses;
$obj = undef;

my $text = read_file($f);
unlike($text, qr/ERRORS:/, '.. found no errors');
like($text, qr/MATCH:/,    '.. found matches');
like($text, qr/PATTERNS:/, '.. found patterns');

### Test Direct Process Methods
