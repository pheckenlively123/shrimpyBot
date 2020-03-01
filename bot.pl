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
    
getopt('c:h', $opts);

foreach my $op ( qw / c / ) {
    if ( !defined ( $opts->{c} ) ) {
	warn "Missing required option: -c\n";
	die $usage;
    }
}

# Now that we have the config file, instantiate the config object.
$confParse = Config::ShrimpConfig->new ( $opts->{c} );

### Subroutine Section ###

### Main Section ###

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

    ### ToDo: Add warm up delay support.

    if ( $acc->{isRebalancing} ) {
	# Skip making changes in strategy, if rebalancing is taking
	# place.  (Yes...I know this could be stale information by the
	# time I act on it...)
	next;
    }

    my $port = $apiWrap->getAllPortfolios ( $acc->{id} );

    if ( defined ( $port->{bear}->{active} )
	 && $port->{bear}->{active} ) {
	
	print "Bear mode currently engaged.\n";
	
    } elsif ( defined ( $port->{bull}->{active} )
	      && $port->{bull}->{active} ) {

	print "Bull mode currently engaged.\n";

    } else {
	confess "Neither bear nor bull modes appear to be active.\n";
    }
	
    print '';
    
}

print '';
