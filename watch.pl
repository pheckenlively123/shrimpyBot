#!/usr/bin/perl -w

### Module Section ###

use lib qw [ . extlib/lib/perl5 ];
use strict;
use warnings;
use Carp;
use Getopt::Std;
use JSON;
use Email::Send;
use Email::Send::Gmail;
use Email::Simple::Creator;
use Config::ShrimpConfig;
use Shrimpy::ApiWrap;
use Data::Dumper;

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

sub writeTimeTrackFile {
    
    my $trackFile = $conf->{watch}->{cooldownTrack};
    
    my $trackRec = { lastEmail => time () };
    my $jText = to_json ( $trackRec );

    open ( my $WT, '>', $trackFile )
	or confess "Failed to open $trackFile for write: $!\n";

    print {$WT} "$jText\n";

    close ( $WT )
	or confess "Failed to close $trackFile from write: $!\n";
    
}

sub emailDelay {

    my $trackFile = $conf->{watch}->{cooldownTrack};
    my $trackRec;
    
    if ( -f $trackFile ) {

	my $jText = '';
	
	open ( my $RD, '<', $trackFile )
	    or confess "Failed to open $trackFile for read: $!\n";

	while ( my $line = <$RD> ) {
	    $jText .= $line;
	}

	close ( $RD )
	    or confess "Failed to close $trackFile from read: $!\n";

	$trackRec = from_json ( $jText );

	if ( ( time () -  $trackRec->{lastEmail} )
	     < ( $conf->{watch}->{cooldown} * 60 ) ) {
	    # do nothing
	} else {	    
	    writeTimeTrackFile ();
	    sendEmail ();
	}
    } else {
	writeTimeTrackFile ();
	sendEmail ();
    }	
}

sub sendEmail {

    my $email = Email::Simple->create(
	header => [
	    From    => $conf->{watch}->{fromEmail},
	    To      => $conf->{watch}->{toEmail},
	    Subject => $conf->{watch}->{toEmailSubject},
	],
	body => "Time to rebalance your shrimpy.  Difference is up to: $difference\n",
	);
    
    my $sender = Email::Send->new(
	{   mailer      => 'Gmail',
	    mailer_args => [
		username => $conf->{watch}->{fromEmail},
		password => $conf->{watch}->{fromEmailPass},
		]
	}
	);
    eval { $sender->send($email) };
    die "Error sending email: $@" if $@;
}

### Main Section ###

$confParse = Config::ShrimpConfig->new ( $opts->{c} );
$conf = $confParse->getConfig ();
$shrimpy = Shrimpy::ApiWrap->new ( $conf );

$accounts = $shrimpy->getAllAccounts ();

foreach my $acc ( @{$accounts} ) {

    # For now, this tool only supports one active exchange at a time.
    if ( $acc->{exchange} ne $conf->{watch}->{activeExchange} ) {
	next;
    }

    # print Dumper ( $acc ) . "\n";

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

if ( $difference > $conf->{watch}->{maxDiff} ) {
    emailDelay ();
}

exit ( 0 );
