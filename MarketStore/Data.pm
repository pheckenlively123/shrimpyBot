package MarketStore::Data;

use strict;
use warnings;
use Carp;
use DBI;

sub new {
    my $class = shift;
    my $conf = shift;

    my $self = {};
    bless $self, $class;
 
    $self->_initialize ( $conf );
   
    return $self;
}

sub _initialize {
    my $self = shift;
    my $conf = shift;

    $self->{conf} = $conf;

    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{conf}->{dbFile}",
				"","");

    # Safe to run the DDL load every time, because we are using the
    # "if not exists" syntax.
    $self->loadDDL ();
}


sub loadDDL {
    my $self = shift;

    # For now, just put all of the market data into a single table.  I
    # don't have enough data for the exchanges to make that a seperate
    # table yet.

    my $sql =<< "EOF";
create table if not exists ticker (
   key INTEGER PRIMARY KEY AUTOINCREMENT,
   exchange text not null,
   name text not null,
   symbol text not null,
   priceUsd real not null,
   priceBtc real not null,
   percentChange24hUsd real not null,
   lastUpdated text not null,
   shortEmaUsd real,
   longEmaUsd real,
   shortEmaBtc real,
   longEmaBtc real,
   bullStatusUsd integer,
   bullStatusBtc integer
)
EOF
    
    my $rv = $self->{dbh}->do ( $sql );

    if ( !defined ( $rv ) ) {
	confess "Failed to load DDL.\n";
    }

    # I think I may need another table to track state for things like
    # warm up delay.  Still mulling this one through...

    # See how performance goes on the queries, before we add indexes.
}

sub dumpDatabase {
    my $self = shift;

    if ( !defined ( $self->{conf}->{dumpFile} ) ) {
	return;
    }

    my $sql =<< "EOF";
select 
    key,
    exchange,
    name,
    symbol,
    priceUsd,
    priceBtc,
    percentChange24hUsd,
    lastUpdated,
    shortEmaUsd,
    longEmaUsd,
    shortEmaBtc,
    longEmaBtc,
    bullStatusUsd,
    bullStatusBtc
from ticker
order by 
    exchange,
    symbol,
    lastUpdated
EOF
	
    open ( my $WT, '>', $self->{conf}->{dumpFile} )
	or confess 
	"Failed to open " . $self->{conf}->{dumpFile} . " for write: $!\n";

    print {$WT} "key,exchange,name,symbol,priceUsd,priceBtc,percentChange24hUsd,lastUpdated,shortEmaUsd,longEmaUsd,shortEmaBtc,longEmaBtc,bullStatusUsd,bullStatusBtc\n";
    
    my $sth = $self->{dbh}->prepare ( $sql );
    $sth->execute ();
    while ( my $res = $sth->fetchrow_arrayref ) {
	my $outLine = "";
	foreach my $col ( @{$res} ) {
	    if ( defined ( $col ) ) {
		$outLine .= $col . ",";
	    } else {
		$outLine .= 'UNDEF' . ",";
	    }
	}
	$outLine =~ s/,$//;

	print {$WT} "$outLine\n";
    }

    close ( $WT )
	or confess 
	"Error closing " . $self->{conf}->{dumpFile} . " from write: $!\n";
}

sub openDump {
    my $self = shift;

    if ( !defined ( $self->{conf}->{dumpFile} ) ) {
	return;
    }
    
    my $cmd = sprintf "soffice %s", $self->{conf}->{dumpFile};

    # This leaves the soffice process in the forground intentionally...
    my $try = system ( $cmd );
    if ( $try != 0 ) {
	confess "Error running \"$cmd\": $!\n";
    }
}

sub loadTicker {
    my $self = shift;
    my $exchange = shift;
    my $ticker = shift;

    # Start by collecting a list of the known names in the database
    # for this exchange.  Use this for gap analysis later.
    my $symSql =<< "EOF";
select distinct symbol from ticker where exchange = ?
EOF

    my $symSth = $self->{dbh}->prepare ( $symSql );
    $symSth->execute ( $exchange );
    my $symCap = {};
    while ( my $rec = $symSth->fetchrow_hashref ) {
	$symCap->{$rec->{symbol}} = 0;
    }
    
    my $sql =<< "EOF";
insert into ticker ( 
   exchange,
   name, 
   symbol, 
   priceUsd, 
   priceBtc, 
   percentChange24hUsd, 
   lastUpdated 
) values ( ?, ?, ?, ?, ?, ?, ? )
EOF
    
    my $sth = $self->{dbh}->prepare ( $sql );

    foreach my $tick ( @{$ticker} ) {
	$sth->execute ( $exchange,
			$tick->{name},
			$tick->{symbol},
			$tick->{priceUsd},
			$tick->{priceBtc},
			$tick->{percentChange24hUsd},
			$tick->{lastUpdated} )
	    or confess "Error executing $sql\n";

	$symCap->{$tick->{symbol}}++;
    }

    my $backGetSql =<< "EOF";
select 
    name, 
    priceUsd, 
    priceBtc, 
    percentChange24hUsd
from ticker
where 
    exchange = ? 
    and symbol = ? 
    and lastUpdated = (select max(lastUpdated) from ticker
where exchange = ? and symbol = ?)
EOF
    my $backGetSth = $self->{dbh}->prepare ( $backGetSql );

    # Add some plumbing to sort out the query parameters below.
    my @names = qw / 
        name
        priceUsd 
        priceBtc 
        percentChange24hUsd 
    /;

    my %nm = ();
    for ( my $i = 0 ; $i <= $#names ; $i++ ) {
	$nm{$names[$i]} = $i;
    }

    # Where we are missing entries, back fill with the last value we
    # received.
    foreach my $symbol ( keys %{$symCap} ) {

	if ( $symCap->{$symbol} == 0 ) {

	    # We need to back fill a missing entry.

	    $backGetSth->execute ( $exchange, $symbol, $exchange, $symbol );
	    my $res = $backGetSth->fetchall_arrayref;

	    # Manufacture a new date/time stamp here to use with the
	    # insert from gmtime.
	    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
		gmtime ( time () );

	    $year += 1900;
	    $mon++;

	    my $synthDate = sprintf '%04d-%02d-%02dT%02d:%02d:%02d.000Z',
	    $year, $mon, $mday, $hour, $min, $sec;
	    
	    $sth->execute ( $exchange,
			    $res->[0]->[$nm{name}],
			    $symbol,
			    $res->[0]->[$nm{priceUsd}],
			    $res->[0]->[$nm{priceBtc}],
			    $res->[0]->[$nm{percentChange24hUsd}],
			    $synthDate )
		or confess "Error executing $sql\n";
	}
    }
}

sub updateEma {
    my $self = shift;
    my $exchange = shift;

    my $sqlName =<< "EOF";
select distinct symbol from ticker where exchange = ?
EOF

    my $sthName = $self->{dbh}->prepare ( $sqlName );

    my $sqlPrices =<< "EOF";
select 
    key,
    priceUsd, 
    priceBtc, 
    lastUpdated,
    shortEmaUsd,
    longEmaUsd,
    shortEmaBtc,
    longEmaBtc,
    bullStatusUsd,
    bullStatusBtc
from 
    ticker 
where 
    exchange = ? and symbol = ?
order by lastUpdated
EOF
    
    my $sthPrices = $self->{dbh}->prepare ( $sqlPrices );

    my $updateEmaSql =<< "EOF";
update ticker set 
    shortEmaUsd   = ?,
    longEmaUsd    = ?,
    shortEmaBtc   = ?,
    longEmaBtc    = ?,
    bullStatusUsd = ?,
    bullStatusBtc = ?
where
    key = ?
EOF

    my $sthUpdateEma = $self->{dbh}->prepare ( $updateEmaSql );
    
    $sthName->execute ( $exchange );
    while ( my $rName = $sthName->fetchrow_hashref ) {

	if ( $self->{conf}->{debugMode} ) {
	    printf "Working on symbol: %s\n", $rName->{symbol};
	}

	$sthPrices->execute ( $exchange, $rName->{symbol} );

	# Later on, we are going to delete rows to get back to the
	# maxHistory configuration parameter, so the entire result set
	# should always be relatively modest in size.
	my @ut = ();
	while ( my $rr = $sthPrices->fetchrow_hashref () ) {
	    push ( @ut, $rr );
	}

	# Using the for loop to get easy access to the previous EMA.
	for ( my $i = 0 ; $i <= $#ut ; $i++ ) {

	    my $sw = 2 / ( $self->{conf}->{shortEma} + 1 );
	    my $lw = 2 / ( $self->{conf}->{longEma} + 1 );

	    if ( $i == 0 ) {

		my $updateFlagZero = 0;

		# Initialize the EMA columns with the current price,
		# since that is all we have.  Once the warm up delay
		# is passed, we should have converged to the actual
		# EMAs.
		
		if ( !defined ( $ut[$i]->{shortEmaUsd} ) ) {
		    $ut[$i]->{shortEmaUsd} = 
			$ut[$i]->{priceUsd};
		    $updateFlagZero = 1;
		}

		if ( !defined ( $ut[$i]->{longEmaUsd} ) ) {
		    $ut[$i]->{longEmaUsd} = 
			$ut[$i]->{priceUsd};
		    $updateFlagZero = 1;
		}

		if ( !defined ( $ut[$i]->{shortEmaBtc} ) ) {
		    $ut[$i]->{shortEmaBtc} = 
			$ut[$i]->{priceBtc};
		    $updateFlagZero = 1;		    
		}
		
		if ( !defined ( $ut[$i]->{longEmaBtc} ) ) {
		    $ut[$i]->{longEmaBtc} = 
			$ut[$i]->{priceBtc};
		    $updateFlagZero = 1;
		}

		if ( !defined ( $ut[$i]->{bullStatusUsd} ) ) {
		    if ( $ut[$i]->{shortEmaUsd} 
			 > $ut[$i]->{longEmaUsd} ) {
			$ut[$i]->{bullStatusUsd} = 1;
		    } else {
			$ut[$i]->{bullStatusUsd} = 0;
		    }
		    $updateFlagZero = 1;
		}

		if ( !defined ( $ut[$i]->{bullStatusBtc} ) ) {
		    if ( $ut[$i]->{shortEmaBtc}
			 > $ut[$i]->{longEmaBtc} ) {
			$ut[$i]->{bullStatusBtc} = 1;
		    } else {
			$ut[$i]->{bullStatusBtc} = 0;
		    }
		    $updateFlagZero = 1;
		}

		# Save what we have so far back into the database, if
		# there are changes.
		if ( $updateFlagZero ) { 
		    $sthUpdateEma->execute (
			$ut[$i]->{shortEmaUsd},
			$ut[$i]->{longEmaUsd},
			$ut[$i]->{shortEmaBtc},
			$ut[$i]->{longEmaBtc},
			$ut[$i]->{bullStatusUsd},
			$ut[$i]->{bullStatusBtc},
			$ut[$i]->{key} );
		    
		}

		# Dislike nested if-than-else structures...
		next;		    
	    }

	    # Only perform the update, if there is something new.
	    my $updateFlag = 0;
	    
	    if ( !defined ( $ut[$i]->{shortEmaUsd} ) ) {
		$ut[$i]->{shortEmaUsd} = 
		    ( $ut[$i]->{priceUsd} * $sw )
		    + ( $ut[$i-1]->{shortEmaUsd} * ( $sw - 1 ) );
		$updateFlag = 1;
	    }
	    
	    if ( !defined ( $ut[$i]->{longEmaUsd} ) ) {
		$ut[$i]->{longEmaUsd} =
		    ( $ut[$i]->{priceUsd} * $lw )
		    + ( $ut[$i-1]->{longEmaUsd} * ( $lw - 1 ) );
		$updateFlag = 1;
	    }
	    
	    if ( !defined ( $ut[$i]->{shortEmaBtc} ) ) {
		$ut[$i]->{shortEmaBtc} = 
		    ( $ut[$i]->{priceBtc} * $sw )
		    + ( $ut[$i-1]->{shortEmaBtc} * ( $sw - 1 ) );
		$updateFlag = 1;
	    }
	    
	    if ( !defined ( $ut[$i]->{longEmaBtc} ) ) {
		$ut[$i]->{longEmaBtc} = 
		    ( $ut[$i]->{priceBtc} * $lw )
		    + ( $ut[$i-1]->{longEmaBtc} * ( $lw - 1 ) );
		$updateFlag = 1;
	    }

	    if ( !defined ( $ut[$i]->{bullStatusUsd} ) ) {
		if ( $ut[$i]->{shortEmaUsd} 
		     > $ut[$i]->{longEmaUsd} ) {
		    $ut[$i]->{bullStatusUsd} = 1;
		} else {
		    $ut[$i]->{bullStatusUsd} = 0;
		}
		$updateFlag = 1;
	    }
	    
	    if ( !defined ( $ut[$i]->{bullStatusBtc} ) ) {
		if ( $ut[$i]->{shortEmaBtc}
		     > $ut[$i]->{longEmaBtc} ) {
		    $ut[$i]->{bullStatusBtc} = 1;
		} else {
		    $ut[$i]->{bullStatusBtc} = 0;
		}
		$updateFlag = 1;
	    }	    
	    
	    # Save what we have so far back into the database, if
	    # there are updates.
	    if ( $updateFlag ) {
		$sthUpdateEma->execute (
		    $ut[$i]->{shortEmaUsd},
		    $ut[$i]->{longEmaUsd},
		    $ut[$i]->{shortEmaBtc},
		    $ut[$i]->{longEmaBtc},
		    $ut[$i]->{bullStatusUsd},
		    $ut[$i]->{bullStatusBtc},
		    $ut[$i]->{key} );
	    }
	}
    }
}

# Clean up the history, so we don't keep it indefinitely.
sub trimHistory {
    my $self = shift;
    my $exchange = shift;

    my $sqlName =<< "EOF";
select distinct name from ticker where exchange = ?
EOF

    my $sthName = $self->{dbh}->prepare ( $sqlName );

    my $sqlAllName =<< "EOF";
select lastUpdated from ticker where exchange = ? and name = ?
order by lastUpdated
EOF

    my $sthAllName = $self->{dbh}->prepare ( $sqlAllName );

    my $sqlDel =<< "EOF";
delete from ticker where exchange = ? and name = ? and lastUpdated = ?
EOF

    my $sthDel = $self->{dbh}->prepare ( $sqlDel );
    
    $sthName->execute ( $exchange );
    while ( my $hr = $sthName->fetchrow_hashref ) {
	
	$sthAllName->execute ( $exchange, $hr->{name} );
	my $alr = $sthAllName->fetchall_arrayref;

	while ( $#{$alr} >= ( $self->{conf}->{maxHistory} - 1) ) {
	    my $row = shift ( @{$alr} );

	    $sthDel->execute ( $exchange, $hr->{name}, $row->[0] );
	}
    }
}

# Dirt simple warm up for now.  If the number of rows for the BTC
# ticker for the specified exchange is greater than the warm up, we
# are out of warm up.  Remove the database file, whenever you want to
# do a warm up period.
sub inWarmUpDelay {
    my $self = shift;
    my $exchange = shift;

    my $sql =<< "EOF";
select count(lastUpdated)
from ticker
where exchange = ? and symbol = 'BTC'
EOF

    my $sth = $self->{dbh}->prepare ( $sql );
    $sth->execute ( $exchange );
    my $res = $sth->fetchall_arrayref ();
    my $count = $res->[0]->[0];

    if ( $count >= $self->{conf}->{warmUpDelay} ) {
	printf "Hit warm up: %d\n", $count;
	return 0;
    } else {
	printf "Still warming: %d\n", $count;
	return 1;
    }
}
    
### The three methods below need to be revisited when I have fewer
### interruptsions....

# return boolean...This triggers going back into bull mode from bear.
sub aboveThresh {
    my $self = shift;
    my $exchange = shift;
    my $port = shift;

    my $bullPer = $self->getPortPercent (
	$port, "bull" );

    printf "Bull percent: %02.2f%%\n", $bullPer;
    
    if ( $bullPer >= $self->{conf}->{startBull} ) {
	return 1;
    } else {
	return 0;
    }
}

# return boolean...This triggers going into bear mode from bull.
sub belowThresh {
    my $self = shift;
    my $exchange = shift;
    my $port = shift;

    my $bullPer = $self->getPortPercent (
	$exchange, $port, "bull" );

    printf "Bull percent: %02.2f%%\n", $bullPer;

    if ( $bullPer <= $self->{conf}->{endBull} ) {
	return 1;
    } else {
	return 0;
    }
}

# Use BTC where available, else use USDT...well...for now just work
# off BTC only...
sub getPortPercent {
    my $self = shift;
    my $exchange = shift;
    my $port = shift;
    my $type = shift;

    my $pr = $port->{$type};

    my $allCount = 0;
    my $bullCount = 0;

    my $sql =<< "EOF";
select 
    bullStatusUsd,
    bullStatusBtc    
from ticker
where 
    exchange = ? 
    and symbol = ? 
    and lastUpdated = (select max(lastUpdated) from ticker
where exchange = ? and symbol = ?)
EOF

    my $sth = $self->{dbh}->prepare ( $sql );

    my $ignore = {};
    my $typeIgnore = $type . "IgnoreList";
    foreach my $ig ( @{$self->{conf}->{$typeIgnore}} ) {
	$ignore->{$ig} = '';
    }

    foreach my $al ( @{$pr->{strategy}->{allocations}} ) {

	if ( defined ( $ignore->{$al->{currency}} ) ) {
	    next;
	}
	
	$sth->execute ( $exchange, $al->{currency},
	    $exchange, $al->{currency} );
	my $res = $sth->fetchrow_hashref;

	if ( $res->{bullStatusBtc} ) {
	    $bullCount++;
	}

	$allCount++;
    }

    my $rv = ( $bullCount / $allCount ) * 100;
    return $rv;
}

1;
