use warnings;
use strict;

package XML::Compile::RPC;
use base 'XML::Compile::Cache';

use Log::Report 'xml-compile-rpc', syntax => 'SHORT';

=chapter NAME
XML::Compile::RPC - base-class for ::Client and ::Server

=chapter SYNOPSIS
 # you should initiate the ::Client

=chapter DESCRIPTION
This class implements commonalities between XML-RPC client and server
implementations.  The server has not been implemented (yet).

=chapter METHODS

=section Constructors

=c_method new OPTIONS
=option opts_rw      ARRAY-OF-PAIRS
=option opts_readers ARRAY-OF-PAIRS
=option opts_writers ARRAY-OF-PAIRS
=cut

sub init($)
{   my ($self, $args) = @_;

    push @{$args->{opts_rw}}, sloppy_floats => 1, sloppy_integers => 1
      , mixed_elements => 'STRUCTURAL';

    push @{$args->{opts_readers}}
      , hooks => [ {type => 'ValueType', replace => \&_rewrite_string}
                 , {type => 'ISO8601', replace  => \&_reader_rewrite_date} ];

    push @{$args->{opts_writers}}
      , hook  =>   {type => 'ISO8601', before  => \&_writer_rewrite_date};

    $self->SUPER::init($args);

    (my $xsd = __FILE__) =~ s,\.pm$,/xml-rpc.xsd,;
    $self->importDefinitions($xsd);

    $self;
}

sub _rewrite_string($$$$$)
{   my ($element, $reader, $path, $type, $replaced) = @_;
#   use Carp; confess $element->childNodes;

      grep( {$_->isa('XML::LibXML::Element')} $element->childNodes)
    ? $replaced->($element)
    : (value => {string => $element->textContent});
}

# xsd:dateTime requires - and : between the components
sub _iso8601_to_dateTime($)
{   my $s = shift;
    $s =~ s/^([12][0-9][0-9][0-9])-?([01][0-9])-?([0-3][0-9])T/$1-$2-$3T/;
    $s =~ s/T([012][0-9]):?([0-5][0-9]):?([0-6][0-9])/T$1:$2:$3/;
    $s;
}

sub _writer_rewrite_date
{   my ($doc, $string, $path) = @_;
    _iso8601_to_dateTime $string;
}

sub _reader_rewrite_date
{   my ($element, $reader, $path, $type, $replaced) = @_;
    my $schema_time = _iso8601_to_dateTime $element->textContent;
    # $schema_time should get validated...
    ('dateTime.iso8601' => $schema_time);
}

1;
