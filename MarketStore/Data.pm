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

    # See how performance goes on the queries, before we add indexes.
}

sub loadTicker {
    my $self = shift;
    my $exchange = shift;
    my $ticker = shift;

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
    }
    print '';
}

sub updateEma {
    my $self = shift;
    my $exchange = shift;

    my $sqlName =<< "EOF";
select distinct name from ticker where exchange = ?
EOF

    my $sthName = $self->{dbh}->prepare ( $sqlName );

    my $sqlPrices =<< "EOF";
select 
    priceUsd, 
    priceBtc, 
    lastUpdated,
    shortEmaUsd,
    longEmaUsd,
    shortEmaBtc,
    longEmaBtc,
    lastUpdated
from 
    ticker 
where 
    exchange = ? and name = ?
order by lastUpdated
EOF

    # Define a helper hash to help make things more readable below.
    my %nm = ();
    my @fieldList = qw /
	priceUsd  
	priceBtc  
	lastUpdated 
	shortEmaUsd 
	longEmaUsd 
	shortEmaBtc 
	longEmaBtc
        lastUpdated
	/;
    
    my $fnum = 0;
    foreach my $field ( @fieldList ) {
	$nm{$field} = $fnum;
	$fnum++;
    }
    
    my $sthPrices = $self->{dbh}->prepare ( $sqlPrices );

    my $updateEmaSql =<< "EOF";
update ticker set 
    shortEmaUsd = ?,
    longEmaUsd  = ?,
    shortEmaBtc = ?,
    longEmaBtc  = ?
where
    exchange = ? 
    and name = ?
    and lastUpdated = ?
EOF

    my $sthUpdateEma = $self->{dbh}->prepare ( $updateEmaSql );
    
    $sthName->execute ( $exchange );
    foreach my $res ( $sthName->fetchrow_hashref ) {

	$sthPrices->execute ( $exchange, $res->{name} );

	# Later on, we are going to delete rows to get back under the
	# maxHistory configuration parameter, so the entire result set
	# should always be relatively modest in size.
	my $prListRef = $sthPrices->fetchall_arrayref;

	for ( my $i = 0 ; $i <= $#{$prListRef} ; $i++ ) {

	    my $shortWeight = 2 / ( $self->{conf}->{shortEma} + 1 );
	    my $longWeight = 2 / ( $self->{conf}->{longEma} + 1 );
	    
	    print '';
	}
    }
}

1;
