package CPAN::Testers::Data::Addresses;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.03';
$|++;

#----------------------------------------------------------------------------
# Library Modules

use base qw(Class::Accessor::Fast);

use CPAN::Testers::Common::DBUtils;
use Config::IniFiles;
use File::Basename;
use File::Path;
use File::Slurp;
use Getopt::Long;
use IO::File;

#----------------------------------------------------------------------------
# Variables

my (%backups);

my %phrasebook = (
    'AllAddresses'          => q{SELECT * FROM tester_address},
    'AllAddressesFull'      => q{SELECT a.*,p.name,p.pause FROM tester_address AS a INNER JOIN tester_profile AS p ON p.testerid=a.testerid},
    'UpdateAddressIndex'    => q{REPLACE INTO ixaddress (id,addressid) VALUES (?,?)},

    'InsertAddress'         => q{INSERT INTO tester_address (testerid,address,email) VALUES (0,?,?)},
    'GetAddressByText'      => q{SELECT addressid FROM tester_address WHERE address = ?},
    'LinkAddress'           => q{UPDATE tester_address SET testerid=? WHERE addressid=?},

    'GetTesterByPause'      => q{SELECT testerid FROM tester_profile WHERE pause = ?},
    'GetTesterByName'       => q{SELECT testerid FROM tester_profile WHERE name = ?},
    'InsertTester'          => q{INSERT INTO tester_profile (name,pause) VALUES (?,?)},

    'AllReports'            => q{SELECT id,tester FROM cpanstats WHERE state IN ('pass','fail','na','unknown') AND id > ? ORDER BY id},
    'GetTestersByMonth'     => q{SELECT DISTINCT tester FROM cpanstats WHERE postdate >= '%s' AND state IN ('pass','fail','na','unknown')},
    'GetTesters'            => q{SELECT DISTINCT tester FROM cpanstats WHERE state IN ('pass','fail','na','unknown')},

    # Database backup requests
    'DeleteBackup'  => 'DELETE FROM addresses',
    'CreateBackup'  => 'CREATE TABLE addresses (testerid int, name text, pause text, PRIMARY KEY (testerid))',
    'SelectBackup'  => 'SELECT * FROM tester_profile',
    'InsertBackup'  => 'INSERT INTO addresses (testerid,name,pause) VALUES (?,?,?)',
);

my %defaults = (
    'address'   => 'data/addresses.txt',
    'mailrc'    => 'data/01mailrc.txt',
    'lastfile'  => 'data/_lastid',
    'month'     => 199000,
    'match'     => 0,
    'logclean'  => 0
);

#----------------------------------------------------------------------------
# The Application Programming Interface

sub new {
    my $class = shift;

    my $self = {};
    bless $self, $class;

    $self->_init_options(@_);
    return $self;
}

sub DESTROY {
    my $self = shift;
}

__PACKAGE__->mk_accessors(qw( lastfile logfile logclean ));

sub process {
    my $self = shift;

    if($self->{options}{update}) {
        $self->update();

    } elsif($self->{options}{reindex}) {
        $self->reindex();

    } elsif($self->{options}{backup}) {
        $self->backup();

    } else {
        $self->search();
    }
}

sub search {
    my $self = shift;
    $self->_log("starting search");

    $self->load_addresses();
    $self->match_addresses();
    $self->print_addresses();

    $self->_log("stopping search");
}

sub update {
    my $self = shift;
    my ($new,$all) = (0,0);
    $self->_log("starting update");

    my $fh = IO::File->new($self->{options}{update})    or die "Cannot open mailrc file [$self->{options}{update}]: $!";
    while(<$fh>) {
        next    unless(/^(\d+),(\d+),([^,]+),([^,]+),([^,]*),/);
        my ($addressid,$testerid,$address,$name,$pause) = ($1,$2,$3,$4,$5);
        unless($address && $name) {
            $self->_log("... bogus line: $_");
            next;
        }

        $all++;
        if($testerid == 0) {
            my @rows;
            @rows = $self->{CPANSTATS}->get_query('hash',$phrasebook{'GetTesterByPause'},$pause)    if($pause);
            unless(@rows) {
                @rows = $self->{CPANSTATS}->get_query('hash',$phrasebook{'GetTesterByName'},$name);
            }

            if(@rows) {
                $testerid = $rows[0]->{testerid};
            } else {
                $testerid = $self->{CPANSTATS}->id_query($phrasebook{'InsertTester'},$name,$pause);
                $new++;
            }
        }

        if($addressid == 0) {
            my @rows = $self->{CPANSTATS}->get_query('hash',$phrasebook{'GetAddressByText'},$address);
            if(@rows) {
                $addressid = $rows[0]->{addressid};
            } else {
                $addressid = $self->{CPANSTATS}->id_query($phrasebook{'InsertAddress'},$address,_extract_email($address));
            }
        }

        $self->{CPANSTATS}->do_query($phrasebook{'LinkAddress'},$testerid,$addressid);
        $self->_log("... profile => address: ($testerid,$name,$pause) => ($addressid,$address)");
    }

    print "$all addresses mapped\n";
    print "$new new addresses\n";

    $self->_log("$all addresses mapped, $new new addresses");
    $self->_log("stopping update");
}

sub reindex {
    my $self = shift;

    # load known addresses
    my %address;
    my $next = $self->{CPANSTATS}->iterator('hash',$phrasebook{'AllAddresses'});
    while( my $row = $next->() ) {
        $address{$row->{address}} = $row->{addressid};
    }

    # search through reports updating the index
    my $lastid = $self->{options}{lastid} || $self->_lastid();
    $next = $self->{CPANSTATS}->iterator('hash',$phrasebook{'AllReports'},$lastid);
    while( my $row = $next->() ) {
        #print STDERR "row: $row->{id} $row->{tester}\n";
        if($address{$row->{tester}}) {
        #print STDERR ".. FOUND\n";
            $self->{CPANSTATS}->do_query($phrasebook{'UpdateAddressIndex'},$row->{id},$address{$row->{tester}});
        } else {
        #print STDERR "..NEW\n";
            $address{$row->{tester}} = $self->{CPANSTATS}->id_query($phrasebook{'InsertAddress'},$row->{tester},_extract_email($row->{tester}));
            $self->{CPANSTATS}->do_query($phrasebook{'UpdateAddressIndex'},$row->{id},$address{$row->{tester}});
        }

        $lastid = $row->{id};
    }
    $self->_lastid($lastid);
}

sub backup {
    my $self = shift;

    for my $driver (keys %{$self->{backups}}) {
        if($self->{backups}{$driver}{'exists'}) {
            $self->{backups}{$driver}{db}->do_query($phrasebook{'DeleteBackup'});
        } elsif($driver =~ /(CSV|SQLite)/i) {
            $self->{backups}{$driver}{db}->do_query($phrasebook{'CreateBackup'});
        }
    }

    $self->_log("Backup via DBD drivers");

    my $rows = $self->{CPANSTATS}->iterator('array',$phrasebook{'SelectBackup'});
    while(my $row = $rows->()) {
        for my $driver (keys %{$self->{backups}}) {
            $self->{backups}{$driver}{db}->do_query($phrasebook{'InsertBackup'},@$row);
        }
    }

    # handle the CSV exception
    if($self->{backups}{CSV}) {
        $self->_log("Backup to CSV file");
        $self->{backups}{CSV}{db} = undef;  # close db handle
        my $fh1 = IO::File->new('addresses','r') or die "Cannot read temporary database file 'addresses'\n";
        my $fh2 = IO::File->new($self->{backups}{CSV}{dbfile},'w+') or die "Cannot write to CSV database file $self->{backups}{CSV}{dbfile}\n";
        while(<$fh1>) { print $fh2 $_ }
        $fh1->close;
        $fh2->close;
        unlink('addresses');
    }
}

sub load_addresses {
    my $self = shift;
    my $next = $self->{CPANSTATS}->iterator('hash',$phrasebook{'AllAddressesFull'});
    while( my $row = $next->() ) {
        $self->{paused_map}{$row->{pause}}   = { name => $row->{name}, pause => $row->{pause}, addressid => $row->{addressid}, testerid => $row->{testerid}, match => '# MAPPED PAUSE' }  if($row->{pause});
        $self->{parsed_map}{$row->{address}} = { name => $row->{name}, pause => $row->{pause}, addressid => $row->{addressid}, testerid => $row->{testerid}, match => '# MAPPED ADDRESS' };
        next    unless($row->{email});
        $self->{address_map}{$row->{email}}  = { name => $row->{name}, pause => $row->{pause}, addressid => $row->{addressid}, testerid => $row->{testerid}, match => '# MAPPED EMAIL' };

        my ($local,$domain) = split(/\@/,$row->{email});
        next    unless($domain);
        $self->{domain_map}{$domain} = { name => $row->{name}, pause => $row->{pause}, addressid => $row->{addressid}, testerid => $row->{testerid}, match => '# MAPPED DOMAIN' };
    }

    if($self->{options}{verbose}) {
        $self->_log( "paused entries  = " . scalar(keys %{ $self->{paused_map}  }) . "\n" );
        $self->_log( "parsed entries  = " . scalar(keys %{ $self->{parsed_map}  }) . "\n" );
        $self->_log( "address entries = " . scalar(keys %{ $self->{address_map} }) . "\n" );
        $self->_log( "domain entries  = " . scalar(keys %{ $self->{domain_map}  }) . "\n" );
    }
    $next = $self->{CPANSTATS}->iterator('hash',$phrasebook{'AllAddresses'});
    while( my $row = $next->() ) {
        next    if($self->{parsed_map}{$row->{address}});
        $self->{stored_map}{$row->{address}} = { name => '', pause => '', addressid => $row->{addressid}, testerid => 0, match => '# STORED ADDRESS' };
    }

    my $fh = IO::File->new($self->{options}{mailrc})    or die "Cannot open mailrc file [$self->{options}{mailrc}]: $!";
    while(<$fh>) {
        s/\s+$//;
        next    if(/^$/);

        my ($alias,$name,$email) = (/alias\s+([A-Z]+)\s+"([^<]+) <([^>]+)>"/);
        next    unless($alias);

        my $testerid  = $self->{address_map}{$email} ? $self->{address_map}{$email}->{testerid}  : 0;
        my $addressid = $self->{address_map}{$email} ? $self->{address_map}{$email}->{addressid} : 0;

        $self->{pause_map}{lc($alias)} = { name => $name, pause => $alias, testerid => $testerid, addressid => $addressid, match => '# PAUSE ID' };
        $self->{cpan_map}{lc($email)}  = { name => $name, pause => $alias, testerid => $testerid, addressid => $addressid, match => '# CPAN EMAIL' };
    }
    $fh->close;

    if($self->{options}{verbose}) {
        $self->_log( "pause entries   = " . scalar(keys %{ $self->{pause_map} }) . "\n" );
        $self->_log( "cpan entries    = " . scalar(keys %{ $self->{cpan_map}  }) . "\n" );
    }

    # grab all records for the month
    my $sql = $self->{options}{month}
        ? sprintf $phrasebook{'GetTestersByMonth'}, $self->{options}{month}
        : $phrasebook{'GetTestersByMonth'};
    if($self->{options}{verbose}) {
        $self->_log( "sql = $sql\n" );
    }
    $next = $self->{CPANSTATS}->iterator('array',$sql);
    $self->{parsed} = 0;
    while(my $row = $next->()) {
        $self->{parsed}++;
        my $email = _extract_email($row->[0]);

        my $testerid  = $self->{parsed_map}{$row->[0]} ? $self->{parsed_map}{$row->[0]}->{testerid}  : 0;
        my $addressid = $self->{parsed_map}{$row->[0]} ? $self->{parsed_map}{$row->[0]}->{addressid} : 0;
        $addressid  ||= $self->{stored_map}{$row->[0]} ? $self->{stored_map}{$row->[0]}->{addressid} : 0;
        $testerid   ||= $self->{address_map}{$email} ? $self->{address_map}{$email}->{testerid}  : 0;
        $addressid  ||= $self->{address_map}{$email} ? $self->{address_map}{$email}->{addressid} : 0;

        next    if($testerid && $addressid);
        
        $self->{unparsed_map}{$row->[0]} = { 
            testerid    => $testerid, 
            addressid   => $addressid, 
            'sort'      => '', 
            email       => $email 
        };
    }

    if($self->{options}{verbose}) {
        $self->_log( "rows = $self->{parsed}\n" );
        $self->_log( "unparsed entries = " . scalar(keys %{ $self->{unparsed_map} }) . "\n" );
    }
}

sub match_addresses {
    my $self = shift;

#    if($self->{options}{verbose}) {
#        use Data::Dumper;
#        $self->_log( "unparsed_map=". Dumper($self->{unparsed_map}) );
#        $self->_log( "parsed_map="  . Dumper($self->{parsed_map}) );
#        $self->_log( "paused_map="  . Dumper($self->{paused_map}) );
#        $self->_log( "pause_map="   . Dumper($self->{pause_map}) );
#        $self->_log( "cpan_map="    . Dumper($self->{cpan_map}) );
#        $self->_log( "domain_map="  . Dumper($self->{domain_map}) );
#        $self->_log( "address_map=" . Dumper($self->{address_map}) );
#        $self->_log( "stored_map="  . Dumper($self->{stored_map}) );
#    }

    for my $key (keys %{ $self->{unparsed_map} }) {
        my $email = _extract_email($key);
        unless($email) {
            push @{$self->{result}{NOEMAIL}}, $key;
            next;
        }
        $email = lc($email);
        my ($local,$domain) = split(/\@/,$email);
#print STDERR "email=[$email], local=[$local], domain=[$domain]\n"  if($email =~ /indiana/);
        next    if($self->map_address($key,$local,$domain,$email));

        my @parts = split(/\./,$domain);
        while(@parts > 1) {
            my $domain2 = join(".",@parts);
#print STDERR "domain2=[$domain2]\n"  if($email =~ /indiana/);
            last    if($self->map_domain($key,$local,$domain2,$email));
            shift @parts;
        }
    }
}

sub print_addresses {
    my $self = shift;
    if($self->{result}{NOMAIL}) {
        print "ERRORS:\n";
        for my $email (sort @{$self->{result}{NOMAIL}}) {
            print "NOMAIL: $email\n";
        }
    }

    print "\nMATCH:\n";
    for my $key (sort {$self->{unparsed_map}{$a} cmp $self->{unparsed_map}{$b}} keys %{ $self->{unparsed_map} }) {
        if($self->{unparsed_map}{$key}->{match}) {
            printf "%d,%d,%s,%s,%s,%s\n", 
                ($self->{unparsed_map}{$key}->{addressid} || 0),
                ($self->{unparsed_map}{$key}->{testerid}  || 0),
                $key,
                ($self->{unparsed_map}{$key}->{name}  || ''),
                ($self->{unparsed_map}{$key}->{pause} || ''),
                ($self->{unparsed_map}{$key}->{match} || '');
            delete $self->{unparsed_map}{$key};
        } else {
            my ($local,$domain) = $self->{unparsed_map}{$key}->{email} =~ /([-+=\w.]+)\@([^\s]+)/;
            ($local,$domain) = $key =~ /([-+=\w.]+)\@([^\s]+)/  unless($local && $domain);
            if($domain) {
                my @parts = split(/\./,$domain);
                $self->{unparsed_map}{$key}{'sort'} = join(".",reverse @parts) . '@' . $local;
            } else {
                print STDERR "FAIL: $key\n";
                $self->{unparsed_map}{$key}{'sort'} = '';
            }
        }
    }

    print "\n";
    return  if($self->{options}{match});

    #use Data::Dumper;
    #print STDERR Dumper(\%{ $self->{unparsed_map} });

    my @mails;
    print "PATTERNS:\n";
    for my $key (sort { $self->{unparsed_map}{$a}{'sort'} cmp $self->{unparsed_map}{$b}{'sort'} } keys %{ $self->{unparsed_map} }) {
        next    unless($key);
        printf "%d,%d,%s,%s,%s,%s\n", 
                ($self->{unparsed_map}{$key}->{addressid} || 0),
                ($self->{unparsed_map}{$key}->{testerid}  || 0),
                $key,
                ($self->{unparsed_map}{$key}->{name}  || ''),
                ($self->{unparsed_map}{$key}->{pause} || ''),
                ($self->{unparsed_map}{$key}->{match} || '') . "\t" . $self->{unparsed_map}{$key}->{'sort'};
    }
}

sub map_address {
    my $self = shift;
    my ($key,$local,$domain,$email) = @_;

    if($self->{address_map}{$key}) {
        $self->{unparsed_map}{$key}->{$_} = $self->{address_map}{$key}->{$_}    for(qw(testerid addressid name pause match));
        return 1;
    }

    if($self->{address_map}{$email}) {
        $self->{unparsed_map}{$key}->{$_} = $self->{address_map}{$email}->{$_}    for(qw(testerid addressid name pause match));
        return 1;
    }

    if($domain eq 'cpan.org') {
        if($self->{pause_map}{$local}) {
            $self->{unparsed_map}{$key}->{$_} = $self->{pause_map}{$local}->{$_}    for(qw(testerid addressid name pause match));
            return 1;
        }
    }

    if($self->{cpan_map}{$email}) {
        $self->{unparsed_map}{$key}->{$_} = $self->{cpan_map}{$email}->{$_}    for(qw(testerid addressid name pause match));
        return 1;
    }

    return 0;
}

sub map_domain {
    my $self = shift;
    my ($key,$local,$domain,$email) = @_;

    for my $filter (@{$self->{filters}}) {
        return 0    if($domain =~ /^$filter$/);
    }

    if($self->{domain_map}{$domain}) {
        $self->{unparsed_map}{$key}->{$_} = $self->{domain_map}{$domain}->{$_}  for(qw(testerid addressid name pause match));
        $self->{unparsed_map}{$key}->{match} .= " - $domain";
        return 1;
    }
    for my $map (keys %{ $self->{domain_map} }) {
        if($map =~ /\b$domain$/) {
            $self->{unparsed_map}{$key}->{$_} = $self->{domain_map}{$map}->{$_}  for(qw(testerid addressid name pause match));
            $self->{unparsed_map}{$key}->{match} .= " - $domain - $map";
            return 1;
        }
    }
    for my $map (keys %{ $self->{domain_map} }) {
        if($domain =~ /\b$map$/) {
            $self->{unparsed_map}{$key}->{$_} = $self->{domain_map}{$map}->{$_}  for(qw(testerid addressid name pause match));
            $self->{unparsed_map}{$key}->{match} .= " - $domain - $map";
            return 1;
        }
    }
    return 0;
}

#----------------------------------------------------------------------------
# Private Methods

sub _lastid {
    my ($self,$id) = @_;
    my $f = $self->lastfile();

    unless( -f $f) {
        mkpath(dirname($f));
        overwrite_file( $f, 0 );
        $id ||= 0;
    }

    if($id) { overwrite_file( $f, $id ); }
    else    { $id = read_file($f); }

    return $id;
}

sub _extract_email {
    my $str = shift;
    my ($email) = $str =~ /([-+=\w.]+\@(?:[-\w]+\.)+(?:com|net|org|info|biz|edu|museum|mil|gov|[a-z]{2,2}))/i;
    return $email || '';
}

sub _init_options {
    my $self = shift;
    my %hash = @_;
    $self->{options} = {};
    my @options = qw(mailrc update reindex lastid backup month match verbose lastfile logfile logclean);

    GetOptions( $self->{options},

        # mandatory options
        'config|c=s',

        # update mode options
        'update|u=s',

        # reindex mode options
        'reindex|r',
        'lastid|l=i',

        # backup mode options
        'backup|b',

        # search mode options
        'mailrc|m=s',
        'month=s',
        'match',

        # other options
        'lastfile=s',
        'verbose|v',
        'help|h'
    ) or $self->_help();

    $self->{options}{$_} ||= $hash{$_}  for(qw(config help),@options);

    $self->_help(1) if($self->{options}{help});
    $self->_help(0) if($self->{options}{version});

    $self->_help(1,"Must specify the configuration file")                       unless(   $self->{options}{config});
    $self->_help(1,"Configuration file [$self->{options}{config}] not found")   unless(-f $self->{options}{config});

    # load configuration
    my $cfg = Config::IniFiles->new( -file => $self->{options}{config} );

    # configure databases
    my %opts;
    my $db = 'CPANSTATS';
    die "No configuration for $db database\n"   unless($cfg->SectionExists($db));
    $opts{$_} = $cfg->val($db,$_)   for(qw(driver database dbfile dbhost dbport dbuser dbpass));
    $self->{$db} = CPAN::Testers::Common::DBUtils->new(%opts);
    die "Cannot configure $db database\n" unless($self->{$db});

    # use configuration settings or defaults if none provided
    for my $opt (@options) {
        $self->{options}{$opt} ||= $cfg->val('MASTER',$opt) || $defaults{$opt};
    }

    # extract filters
    my $filters = $cfg->val('DOMAINS','filters');
    my @filters = split("\n", $filters) if($filters);
    $self->{filters} = \@filters        if(@filters);

    # mandatory options
    #for my $opt (qw()) {
    #    $self->_help(1,"No $opt configuration setting given, see help below.")                          unless(   $self->{options}{$opt});
    #    $self->_help(1,"Given $opt file [$self->{options}{$opt}] not a valid file, see help below.")    unless(-f $self->{options}{$opt});
    #}

    # options to check if provided
    for my $opt (qw(update mailrc)) {
        next                                                                                            unless(   $self->{options}{$opt});
        $self->_help(1,"Given $opt file [$self->{options}{$opt}] not a valid file, see help below.")    unless(-f $self->{options}{$opt});
    }

    # configure backup DBs
    if($self->{options}{backup}) {
        $self->help(1,"No configuration for BACKUPS with backup option")    unless($cfg->SectionExists('BACKUPS'));

        my @drivers = $cfg->val('BACKUPS','drivers');
        for my $driver (@drivers) {
            $self->help(1,"No configuration for backup option '$driver'")   unless($cfg->SectionExists($driver));

            %opts = ();
            $opts{$_} = $cfg->val($driver,$_)   for(qw(driver database dbfile dbhost dbport dbuser dbpass));
            $self->{backups}{$driver}{'exists'} = $driver =~ /SQLite/i ? -f $opts{database} : 1;

            # CSV is a bit of an oddity!
            if($driver =~ /CSV/i) {
                $self->{backups}{$driver}{'exists'} = 0;
                $self->{backups}{$driver}{'dbfile'} = $opts{dbfile};
                $opts{dbfile} = 'uploads';
                unlink($opts{dbfile});
            }

            $self->{backups}{$driver}{db} = CPAN::Testers::Common::DBUtils->new(%opts);
            $self->help(1,"Cannot configure BACKUPS database for '$driver'")   unless($self->{backups}{$driver}{db});
        }
    }

    # clean up potential rogue characters
    $self->{options}{lastid} =~ s/\D+//g    if($self->{options}{lastid});

    # prime accessors
    $self->lastfile($self->{options}{lastfile});
    $self->logfile($self->{options}{logfile});
    $self->logclean($self->{options}{logclean});

    return  unless($self->{options}{verbose});
    print STDERR "config: $_ = ".($self->{options}{$_}||'')."\n"  for(@options);
}

sub _help {
    my ($self,$full,$mess) = @_;

    print "\n$mess\n\n" if($mess);

    if($full) {
        print "\n";
        print "Usage:$0 [--verbose|v] --config|c=<file> \\\n";
        print "         ( [--help|h] \\\n";
        print "         | [--update] \\\n";
        print "         | [--reindex] [--lastid=<num>] \\\n";
        print "         | [--backup] \\\n";
        print "         | [--mailrc|m=<file>] [--month=<string>] [--match] ) \\\n";
        print "         [--logfile=<file>] [--logclean=(0|1)] \n\n";

#              12345678901234567890123456789012345678901234567890123456789012345678901234567890
        print "This program manages the cpan-tester addresses.\n";

        print "\nFunctional Options:\n";
        print "   --config=<file>           # path/file to configuration file\n";
        print "  [--mailrc=<file>]          # path/file to mailrc file\n";

        print "\nUpdate Options:\n";
        print "  [--update]                 # run in update mode\n";

        print "\nReindex Options:\n";
        print "  [--reindex]                # run in reindex mode\n";
        print "  [--lastid=<num>]           # id to start reindex from\n";

        print "\nBackup Options:\n";
        print "  [--backup]                 # run in backup mode\n";

        print "\nSearch Options:\n";
        print "  [--month=<string>]         # YYYYMM string to match from\n";
        print "  [--match]                  # display matches only\n";

        print "\nOther Options:\n";
        print "  [--verbose]                # turn on verbose messages\n";
        print "  [--help]                   # this screen\n";

        print "\nFor further information type 'perldoc $0'\n";
    }

    print "$0 v$VERSION\n";
    exit(0);
}

sub _log {
    my $self = shift;
    my $log = $self->logfile or return;
    mkpath(dirname($log))   unless(-f $log);

    my $mode = $self->logclean ? 'w+' : 'a+';
    $self->logclean(0);

    my @dt = localtime(time);
    my $dt = sprintf "%04d/%02d/%02d %02d:%02d:%02d", $dt[5]+1900,$dt[4]+1,$dt[3],$dt[2],$dt[1],$dt[0];

    my $fh = IO::File->new($log,$mode) or die "Cannot write to log file [$log]: $!\n";
    print $fh "$dt ", @_, "\n";
    $fh->close;
}

q!Will code for a damn fine Balti!;

__END__

#----------------------------------------------------------------------------

=head1 NAME

CPAN::Testers::Data::Addresses - CPAN Testers Addresses Database Manager

=head1 SYNOPSIS

  perl addresses.pl \
        [--verbose|v] --config|c=<file> \
        ( [--help|h] \
        | [--update] \
        | [--reindex] [--lastid=<num>] \
        | [--backup] \
        | [--mailrc|m=<file>] [--month=<string>] [--match] ) \
        [--logfile=<file>] [--logclean=(0|1)]

=head1 DESCRIPTION

This program allows the user to update the tester addresses database, or
search it, based on a restricted set of criteria.

=head1 SCHEMA

The schema for the MySQL database is below:

    CREATE TABLE ixaddress (
        id          int(10) unsigned NOT NULL,
        addressid   int(10) unsigned NOT NULL,
      PRIMARY KEY  (id)
    ) ENGINE=MyISAM;

    CREATE TABLE tester_address (
        addressid   int(10) unsigned NOT NULL auto_increment,
        testerid    int(10) unsigned NOT NULL default 0,
        address     varchar(255) NOT NULL,
        email	varchar(255) default NULL,
      PRIMARY KEY  (addressid)
    ) ENGINE=MyISAM;

    CREATE TABLE tester_profile (
        testerid    int(10) unsigned NOT NULL auto_increment,
        name	varchar(255) default NULL,
        pause	varchar(255) default NULL,
      PRIMARY KEY  (testerid)
    ) ENGINE=MyISAM;

The address field is the same as the tester field in the cpanstats table, while
the email field is the extracted email address field only.

=head1 INTERFACE

=head2 The Constructor

=over

=item * new

Instatiates the object CPAN::Testers::Data::Addresses:

  my $obj = CPAN::Testers::Data::Addresses->new();

=back

=head2 Public Methods

=over

=item * process

Based on accessor settings will run the appropriate methods for the current
execution.

=item * search

Search the tables for unmapped entries, suggesting appropriate mappings.

=item * update

Updates the tester_profiles and tester_address entries as defined by the
reference source text file.

=item * reindex

Indexes the ixaddress table, updating the tester_address table if appropriate.

=item * backup

Provides backup files of the uploads database.

=back

=head2 Accessor Methods

=over

=item * logfile

Path to output log file for progress and debugging messages.

=item * logclean

If set to a true value will create/overwrite the logfile, otherwise will
append any messages.

=item * lastfile

Path to the file containing the last NNTPID processed.

=back

=head2 Internal Methods

=over 4

=item load_addresses

Loads all the data files with addresses against we can match, then load all
the addresses listed in the DB that we need to match against.

=item match_addresses

Given all the possible mappings, attempts to match unmapped addresses.

=item print_addresses

Prints the suggested mappings, and those remaining unmapped addresses.

=item map_address

Atempts to map an address to a known CPAN author, then to one that already 
exists in the database, and finally to one that is known within the CPAN 
Authors index.

=item map_domain

Attempts to map an address based on its domain.

=back

=cut

=head2 Private Methods

=over

=item * _lastid

Sets or returns the last NNTPID processed.

=item * _extract_email

Extracts an email from a text string.

=item * _init_options

Initialises internal configuration settings based on command line options, API
options and configuration file settings.

=item * _help

Provides a help screen.

=item * _log

Writes audit messages to a log file.

=back

=head1 BECOME A TESTER

Whether you have a common platform or a very unusual one, you can help by
testing modules you install and submitting reports. There are plenty of
module authors who could use test reports and helpful feedback on their
modules and distributions.

If you'd like to get involved, please take a look at the CPAN Testers Wiki,
where you can learn how to install and configure one of the recommended
smoke tools.

For further help and advice, please subscribe to the the CPAN Testers
discussion mailing list.

  CPAN Testers Wiki
    - http://wiki.cpantesters.org
  CPAN Testers Discuss mailing list
    - http://lists.cpan.org/showlist.cgi?name=cpan-testers-discuss

=head1 BUGS, PATCHES & FIXES

There are no known bugs at the time of this release. However, if you spot a
bug or are experiencing difficulties, that is not explained within the POD
documentation, please send an email to barbie@cpan.org. However, it would help
greatly if you are able to pinpoint problems or even supply a patch.

Fixes are dependant upon their severity and my availablity. Should a fix not
be forthcoming, please feel free to (politely) remind me.

RT Queue -
http://rt.cpan.org/Public/Dist/Display.html?Name=CPAN-Testers-Data-Addresses

=head1 SEE ALSO

L<CPAN::Testers::Data::Generator>,
L<CPAN::Testers::WWW::Statistics>

F<http://www.cpantesters.org/>,
F<http://stats.cpantesters.org/>,
F<http://wiki.cpantesters.org/>,
F<http://blog.cpantesters.org/>

=head1 AUTHOR

  Barbie, <barbie@cpan.org>
  for Miss Barbell Productions <http://www.missbarbell.co.uk>.

=head1 COPYRIGHT AND LICENSE

  Copyright (C) 2009 Barbie for Miss Barbell Productions.

  This module is free software; you can redistribute it and/or
  modify it under the same terms as Perl itself.

=cut
