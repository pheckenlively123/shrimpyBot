package Shrimpy::ApiWrap;

use strict;
use warnings;
use Carp;
use LWP::UserAgent;
use Time::HiRes qw / nanosleep gettimeofday usleep /;
use Crypt::Mac::HMAC;
use MIME::Base64;
use JSON;
use Data::Dumper;

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
    $self->{ua} = LWP::UserAgent->new ();
    $self->{ua}->agent ( "gumbo/0.0001" );
}

sub _getNonce {

    my ($seconds, $microseconds) = gettimeofday;

    my $retVal = $seconds * 1000000;
    $retVal += $microseconds;

    return $retVal;
}

sub _standardGet {
    my $self = shift;
    my $uriPath = shift;
    
    # Sleep at the top of every REST call, so we don't forget to do it.
    usleep ( $self->{conf}->{restApiDelay} );

    # Prep the crypto bits.
    my $secret = decode_base64 ( $self->{conf}->{apiSecret} );
    my $nonce = $self->_getNonce ();
    my $d = Crypt::Mac::HMAC->new('SHA256', $secret);    
    $d->add ( $uriPath );
    $d->add ( "GET" );    
    $d->add ( $nonce );
    my $hmac = encode_base64 ( $d->mac () );
    chomp ( $hmac );

    # Now that the crypto is finished, prepare a GET call to the
    # endpoint.
    my $uri = $self->{conf}->{apiBaseUrl} . $uriPath;
    my $req = HTTP::Request->new ( 'GET', $uri );
    $req->content_type('application/json');
    $req->header ( 'SHRIMPY-API-KEY' => $self->{conf}->{apiKey} );
    $req->header ( 'SHRIMPY-API-NONCE' => $nonce );
    $req->header ( 'SHRIMPY-API-SIGNATURE' => $hmac );
    
    my $res = $self->{ua}->request ( $req );

    if ( !$res->is_success ) {
	confess Dumper ( $res ) . "\n";
    }

    my $rv = from_json ( $res->content () );

    return $rv;
}

# GET https://api.shrimpy.io/v1/accounts

sub getAllAccounts {
    my $self = shift;

    my $uriPath = sprintf "%s/%s", $self->{conf}->{apiBasePath}, "accounts";
    
    my $rv = $self->_standardGet ( $uriPath );
    
    return $rv;
}

# GET https://api.shrimpy.io/v1/<exchange>/ticker

sub getTicker {
    my $self = shift;
    my $exchange = shift;
    
    # Sleep at the top of every REST call, so we don't forget to do it.
    usleep ( $self->{conf}->{restApiDelay} );
    
    my $uri = sprintf "%s%s/%s/ticker", $self->{conf}->{apiBaseUrl},
    $self->{conf}->{apiBasePath}, $exchange;

    my $req = HTTP::Request->new ( 'GET', $uri );
    $req->content_type('application/json');

    my $res = $self->{ua}->request ( $req );

    if ( !$res->is_success ) {
	confess Dumper ( $res ) . "\n";
    }

    my $rv = from_json ( $res->content () );

    return $rv;
}

# GET https://api.shrimpy.io/v1/accounts/<exchangeAccountId>/portfolios

# Only returns the bear and bull portfolios, as identified by the bear
# and bull suffixes from the config.
sub getPortfolios {
    my $self = shift;
    my $id = shift;

    my $uriPath = sprintf "%s/accounts/%s/portfolios", $self->{conf}->{apiBasePath}, $id;

    my $found = $self->_standardGet ( $uriPath );

    my $rv = {};
    
    # Only return the bull and bear portfolios.
    foreach my $port ( @{$found} ) {

	if ( defined ( $rv->{bear} )
	     && defined ( $rv->{bull} ) ) {
	    last;
	}
	
	if ( $port->{name} =~ /$self->{conf}->{bearSuffix}$/i ) {
	    $rv->{bear} = $port;
	    next;
	}
	
	if ( $port->{name} =~ /$self->{conf}->{bullSuffix}$/i ) {
	    $rv->{bull} = $port;
	    next;
	}
    }

    # Make sure we found both the bear and bull portfolios.
    foreach my $rc ( qw / bear bull / ) {
	if ( !defined ( $rv->{$rc} ) ) {
	    confess "Failed to find portfolio for $rc suffix.\n";
	}
    }

    return $rv;
}
    
1;
