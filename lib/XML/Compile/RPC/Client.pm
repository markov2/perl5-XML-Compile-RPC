use warnings;
use strict;

package XML::Compile::RPC::Client;
use base 'XML::Compile::RPC';

use Log::Report 'xml-compile-rpc';
use XML::Compile::RPC::Util  qw/fault_code/;
use Time::HiRes              qw/gettimeofday tv_interval/;
use HTTP::Request            ();
use LWP::UserAgent           ();

=chapter NAME
XML::Compile::RPC::Client - XML-RPC based on unofficial schema

=chapter SYNOPSYS
 my $rpc = XML::Compile::RPC::Client->new
   ( destination => $service_uri
   , xmlformat   => 1
   , autoload_underscore_is => '-'
   );

 # Call the server
 my ($rc, $answer) = $rpc->call($procedure, @param_pairs);
 $rc==0 or die "error: $response";

 # explict and autoload examples of the same.
 my ($rc, $answer) = $rpc->call('getQuote", symbol => 'IBM');
 my ($rc, $answer) = $rpc->getQuote(symbol => 'IBM');

 # Data::Dumper is your friend
 use Data::Dumper;
 $Data::Dumper::Indent = 1;
 print Dumper $answer;

 # Many useful functions in XML::Compile::RPC::Util
 use XML::Compile::RPC::Util;
 if($answer->{array})
 {   my @a = rpcarray_values $answer->{array};
 }

 # Retreive detailed trace of last call
 my $trace = $rpc->trace;
 print $trace->{response}->as_string;
 print "$trace->{total_elapse}\n";

 # clean-up of connection depends on LWP
 undef $rpc;

=chapter DESCRIPTION
Client XML-RPC implementation, based on an unofficial XML-RPC schema. The
schema used is an extended version from one produced by Elliotte Rusty Harold.

Using the schema with M<XML::Compile> means that the messages are validated.
Besides, XML::Compile offers you some tricks: for instance, you can pass
a C<time()> result (seconds since epoc)to a C<dateTime.iso8601> field,
which will automaticallu get formatted into the right format.

In XML-RPC, values which do not explicitly specify their type are
interpreted as string. So, you may encounter two notations for the
same:

    <value><string>Hello, World!</string></value>
    <value>Hello, World!</value>

The reader (used to produce the C<$response>) will translate the second
syntax in the first. This simplifies your code.

=chapter METHODS

=section Constructors

=c_method new OPTIONS

=requires destination URI
The address of the XML-RPC server.

=option  user_agent OBJECT
=default user_agent <created internally>
You may pass your own L<LWP::UserAgent> object, fully loaded with your
own settings. When you do not, one will be created for you.

=option  xmlformat 0|1|2
=default xmlformat 0
M<XML::LibXML> has three different output formats. Format C<0> is the
most condense, and C<1> is nicely indented. Of course, a zero value is
fastest.

=option  http_header ARRAY|OBJECT
=default http_header []
Additional headers for the HTTP request.  This is either an ARRAY of
key-value pairs, or an M<HTTP::Headers> OBJECT.

=option  autoload_underscore_is STRING
=default autoload_underscore_is '_'
When calls are made using the autoload mechanism, then you will encounter
problems when the method names contain dashes. So, with this option, you
can use underscores which will B<all> be replaced to STRING value specified.
=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{user_agent}  = $args->{user_agent} || LWP::UserAgent->new;
    $self->{xmlformat}   = $args->{xmlformat}  || 0;
    $self->{auto_under}  = $args->{autoload_underscore_is};
    $self->{destination} = $args->{destination}
        or report ERROR => __x"client requires a destination parameter";

    # convert header template into header object
    my $headers = $args->{http_header};
    $headers    = HTTP::Headers->new(@{$headers || []})
        unless UNIVERSAL::isa($headers, 'HTTP::Headers');

    # be sure we have a content-type
    $headers->content_type
        or $headers->content_type('text/xml');

    $self->{headers}     = $headers;

    # only declared methods are accepted by the Cache
    $self->declare(WRITER => 'methodCall');
    $self->declare(READER => 'methodResponse');

    $self;
}

=section Handlers

=method trace
Returns a HASH with various facts about the last call; timings,
the request and the response from the server. Be aware that C<LWP>
will add some more header lines to the request before it is sent.
=cut

my %trace;
sub trace() {\%trace}

=method printTrace [FILEHANDLE]
Pretty print the trace, by default to STDERR.
=cut

sub printTrace(;$)
{   my $self = shift;
    my $fh   = shift || \*STDERR;

    $fh->print("response: ",$trace{response}->status_line, "\n");
    $fh->print("elapse:   $trace{total_elapse}\n");
}

=method call METHOD, PARAM-PAIRS

=example
 my ($rc, $response) = $rpc->call('getQuote', string => 'IBM');
 $rc == 0
     or die "error: $response\n";
 my $trace = $rpc->trace;  # facts about the last call

 # same call, via autoload
 my ($rc, $response) = $rpc->getQuote(string => 'IBM');
=cut

sub call($@)
{   my $self    = shift;
    my $start   = [gettimeofday];
    my $request = $self->_request($self->_callmsg(@_));
    my $format  = [gettimeofday];
    my $response  = $self->{user_agent}->request($request);
    my $network = [gettimeofday];
    
    %trace      =
      ( request        => $request
      , response       => $response
      , start_time     => ($start->[0] + $start->[1]*10e-6)
      , format_elapse  => tv_interval($start, $format)
      , network_elapse => tv_interval($format, $network)
      );

   $response->is_success
      or return ($response->code, $response->status_line);

   my ($rc, $decoded) = $self->_respmsg($response->decoded_content);
   $trace{decode_elapse} = tv_interval $network;
   $trace{total_elapse}  = tv_interval $start;

   ($rc, $decoded);
}

sub _callmsg($@)
{   my ($self, $method) = (shift, shift);

    my @params;
    while(@_)
    {   my ($type, $value) = (shift, shift);
        push @params, { value => { $type => $value }};
    }

    my $doc = XML::LibXML::Document->new('1.0', 'UTF-8');
    my $xml = $self->writer('methodCall')->($doc
      , { methodName => $method, params => { param => \@params }});
    $doc->setDocumentElement($xml);
    $doc;
}

sub _request($)
{   my ($self, $doc) = @_;
    HTTP::Request->new
      ( POST => $self->{destination}
      , $self->{header}
      , $doc->toString($self->{xmlformat})
      );
}

sub _respmsg($)
{   my ($self, $xml) = @_;
    my $data = $self->reader('methodResponse')->($xml);
    return fault_code $data->{fault}
        if $data->{fault};

    my ($type, $value) = %{$data->{params}{param}{value}};
    (0, $value);
}

sub AUTOLOAD
{   my $self  = shift;
    (my $proc = our $AUTOLOAD) =~ s/.*\:\://;
    $proc =~ s/_/$self->{auto_under}/g
        if defined $self->{auto_under};
    $self->call($proc, @_);
}

sub DESTROY {}   # avoid DESTROY to AUTOLOAD
1;
