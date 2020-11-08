package Config::ShrimpConfig;

use strict;
use warnings;
use Carp;
use XML::LibXML;

# Config wrapper

sub new {
    my $class = shift;
    my $cfile = shift;

    if ( $cfile =~ /-example\.xml$/ ) {
	my $barf =<< "EOF";
It appears you tried to run the shrimpy bot with the example config.
If you put our API key and secret in the example config, TAKE THEM OUT NOW.
The example config is tracked by git, and you might accidentally commit
your API key and secret.
EOF
	confess $barf;
    }
    
    my $self = {};
    bless $self, $class;
 
    $self->_initialize ( $cfile );
   
    return $self;
}

sub _initialize {
    my $self = shift;
    my $cfile = shift;

    $self->{dom} = XML::LibXML->load_xml ( location => $cfile );
}

sub _getXPathText {
    my $self = shift;
    my $xpath = shift;

    my @nodeList = $self->{dom}->findnodes ( $xpath );

    if ( $#nodeList != 0 ) {
	confess "Found unexpected number of nodes for: $xpath\n";
    }

    my $foundNode = $nodeList[0];
    return $foundNode->textContent;
}

sub _getConfSection {
    my $self = shift;
    my $section = shift;

    my $rv = {};

    my $xpath = '/config/' . $section;
    my @nodeList = $self->{dom}->findnodes ( $xpath );

    if ( $#nodeList != 0 ) {
	confess "Found unexpected number of nodes for: $xpath\n";
    }

    my @kids = $nodeList[0]->childNodes ();

    foreach my $kid ( @kids ) {

	if ( !$kid->isa ( 'XML::LibXML::Element' ) ) {
	    next;
	}

	my $kidName = $kid->nodeName;
	my $kidValue = $kid->textContent;

	if ( ( $section eq 'watch' ) && ( $kidName eq 'portfolios' ) ) {
	    my @portList = split ( /,/, $kidValue );
	    $kidValue = \@portList;
	}

	$rv->{$kidName} = $kidValue;
    }

    return $rv;
}
    

sub getConfig {
    my $self = shift;

    my $rv = {};
    
    foreach my $section ( qw / base switch watch logging / ) {
	$rv->{$section} = $self->_getConfSection ( $section );
    }
    
    return $rv;
}

# Todo...write some unit test this module...

1;
