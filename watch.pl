#!/usr/bin/perl -w

### Module Section ###

use strict;
use warnings;
use Carp;
use Getopt::Std;
use lib qw [ . ];
use Config::ShrimpConfig;
use Shrimpy::ApiWrap;

### Global Variable Section ###

my $confParse;
my $conf;
my $usage;
my $opts = {};
my $shrimpy;
my $accounts;
my %balTrack = ();
my $total = 0;
my $accountCount = 0;
my $difference = 0;
my $printLine = '';

### Command Line Parse Section ###

$usage =<< "EOF";
watch.pl -c CONF [-h]
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

sub logLine {
    my $logLine = shift;

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
	localtime( time () );

    $mon++;
    $year += 1900;

    my $dateLine = sprintf "%04d-%02d-%02dT%02d:%02d:%02d\t%s",
	$year, $mon, $mday, $hour, $min, $sec, $logLine;

    my $logFile = sprintf "%s/%s-%04d-%02d-%02d", $conf->{logging}->{logDir},
	$conf->{logging}->{logPrefix}, $year, $mon, $mday;

    open ( my $WT, '>>', $logFile )
	or confess "Failed to open $logFile for append: $!\n";

    print {$WT} "$dateLine\n";

    close ( $WT )
	or confess "Failed to close $logFile from append: $!\n";
}

### Main Section ###

$confParse = Config::ShrimpConfig->new ( $opts->{c} );
$conf = $confParse->getConfig ();
$shrimpy = Shrimpy::ApiWrap->new ( $conf );

$accounts = $shrimpy->getAllAccounts ();

foreach my $acc ( @{$accounts} ) {
    
    my $balList = $shrimpy->getBalance ( $acc->{id} );
    
    foreach my $coin ( @{$balList->{balances}} ) {
	
	if ( !defined ( $balTrack{$acc->{id}} ) ) {
	    $balTrack{$acc->{id}} = 0;
	}

	$balTrack{$acc->{id}} += $coin->{btcValue};
    }
}

foreach my $acc ( keys %balTrack ) {
    $total += $balTrack{$acc};
    $accountCount++;
}


foreach my $acc ( sort keys %balTrack ) {
    my $per = $balTrack{$acc} / $total;
    $per = $per * 100;

    $printLine .= sprintf "$acc has %02.2f%%\t", $per;

    $difference += abs ( ( 100 / $accountCount ) - $per );
}

$printLine .= sprintf "Difference is: %f", $difference;
logLine ( $printLine );

exit ( 0 );
