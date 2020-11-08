#!/usr/bin/perl -w

### Module Section ###

use strict;
use warnings;
use Carp;
use Getopt::Std;
use lib qw [ . ];
use Config::ShrimpConfig;
use Shrimpy::ApiWrap;
use MarketStore::Data;

### Global Variable Section ###

my $confParse;
my $conf;
my $usage;
my $opts = {};
my $apiWrap;
my $mark;

### Command Line Parse Section ###

$usage =<< "EOF";
bot.pl -c CONF [-h]
    -c CONF Configuration file to use.
    [-h]    Display usage, and exit.

EOF
    
getopt('hc:', $opts);

if ( defined ( $opts->{h} ) ) {
    print $usage;
    exit ( 0 );
}

foreach my $op ( qw / c / ) {
    if ( !defined ( $opts->{c} ) ) {
	warn "Missing required option: -$op\n";
	die $usage;
    }
}

### Subroutine Section ###

### Main Section ###

confess "Update this code base to account for the changes in the config wrapper, before you use this.\n";

$confParse = Config::ShrimpConfig->new ( $opts->{c} );
$conf = $confParse->getConfig ();
$mark = MarketStore::Data->new ( $conf );
$apiWrap = Shrimpy::ApiWrap->new ( $conf );

my $accountListRef = $apiWrap->getAllAccounts ();

foreach my $acc ( @{$accountListRef} ) {
    my $exName = lc ( $acc->{exchange} );
    my $tick = $apiWrap->getTicker ( $exName );
    $mark->loadTicker ( $exName, $tick );
    $mark->updateEma ( $exName );
    $mark->trimHistory ( $exName );

    # We don't have enough data for meaningful trading decisions yet.
    if ( $mark->inWarmUpDelay ( $exName ) ) {
	next;
    }

    if ( $acc->{isRebalancing} ) {
	# Skip making changes in strategy, if rebalancing is taking
	# place.  
	next;
    }

    my $port = $apiWrap->getPortfolios ( $acc->{id} );

    if ( defined ( $port->{bear}->{active} )
	 && $port->{bear}->{active} ) {
	
	print "Bear mode currently engaged.\n";

	if ( $mark->aboveThresh ( $exName, $port ) ) {
	    # Active bull portfolio
	    print "Activating bull portfolio.\n";
	} else {
	    print "Stay in in bear mode.\n";
	}
	
	
    } elsif ( defined ( $port->{bull}->{active} )
	      && $port->{bull}->{active} ) {

	print "Bull mode currently engaged.\n";

	if ( $mark->belowThresh ( $exName, $port ) ) {
	    #activate bear portfolio
	    print "Activating bear portfolio.\n";
	} else {
	    print "Stay in bull mode.\n";
	}

    } else {
	confess "Neither bear nor bull modes appear to be active.\n";
    }
}

# These next two return without doing anything, as long as the
# <dumpFile> node is commented out in the config.
$mark->dumpDatabase ();
#$mark->openDump ();

exit ( 0 );
