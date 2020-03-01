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
}

print '';
