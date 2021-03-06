# This code is part of distribution XML-Compile-RPC.  Meta-POD processed
# with OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package XML::Compile::RPC::Util;
use base 'Exporter';

use warnings;
use strict;

our @EXPORT = qw/
   struct_to_hash
   struct_to_rows
   struct_from_rows
   struct_from_hash

   rpcarray_values
   rpcarray_from

   fault_code
   fault_from
  /;

=chapter NAME
XML::Compile::RPC::Util - XML-RPC convenience functions

=chapter SYNOPSIS
 use XML::Compile::RPC::Util;

 my $h  = struct_to_hash $d->{struct};
 my @r  = struct_to_rows $d->{struct};
 my $d  = struct_from_rows @r;
 my $d  = struct_from_hash int => %h;

 my @a  = rpcarray_values $d->{array};
 my $d  = rpcarray_from int => @a;

 my $rc = fault_code $d->{fault};
 my ($rc, $rcmsg) = fault_code $d->{fault};

 my $d  = fault_from $rc, $msg;

=chapter DESCRIPTION

=chapter Functions

=section Struct

=function struct_to_hash $struct
Returns a HASH containing the structure information. The order of the
keys and type of the values is lost. When keys appear more than once,
only the last one is kept.

=example
   if(my $s = $d->{struct})
   {   my $h = struct_to_hash $s;
       print "$h->{limit}\n";
   }
=cut

sub struct_to_hash($)
{   my $s = shift;
    my %h;

    foreach my $member ( @{$s->{member} || []} )
    {   my ($type, $value) = %{$member->{value}};
        $h{$member->{name}} = $value;
    }

    \%h;
}

=function struct_to_rows $struct
Returns a LIST of all the members of the structure. Each element of the
returned LIST is an ARRAY with contains three fields: member name,
member type and member value.

=example
   if(my $s = $d->{struct})
   {   my @rows = struct_to_rows $s;
       foreach my $row (@rows)
       {   my ($key, $type, $value) = @$row;
           print "$key: $value ($type)\n";
       }
   }
=cut

sub struct_to_rows($)
{   my $s = shift;
    my @r;

    foreach my $member ( @{$s->{member} || []} )
    {   my ($type, $value) = %{$member->{value}};
        push @r, [ $member->{name}, $type, $value ];
    }

    @r;
}

=function struct_from_rows $row, $row, ...
Each $row is an ARRAY which contains member name, member type, and member
value. Returned is a structure.

=example
   $d = struct_from_rows [symbol => string => 'RHAT']
                       , [limit => double => 2.25];
   print Dumper $d;

prints:

   { struct => { member =>
      [ { name => 'symbol', value => {string => 'RHAT' }}
      , { name => 'limit', value => {double => 2.25} }
      ] }};

which will become in XML

   <struct>
     <member>
       <name>symbol</name>
       <value><string>RHAT</string></value>
     </member>
     <member>
       <name>limit</name>
       <value><double>2.25</double></value>
     </member>
   </struct>

=cut

sub struct_from_rows(@)
{   my @members = map +{name => $_->[0], value => {$_->[1] => $_->[2]}}, @_;
   +{ struct => {member => \@members} };
}

=function struct_from_hash $type, HASH
Only usable when all key-value pairs are of the same type, usually C<string>.
The keys are included alphabetically.
=example
  my $data = struct_from_hash int => { begin => 3, end => 5 };
=cut

sub struct_from_hash($$)
{   my ($type, $hash) = @_;
    my @members = map { +{name => $_, value => {$type => $hash->{$_}}} }
        sort keys %{$hash || {}};
   +{ struct => {member => \@members} };
}

=section Array

=function rpcarray_values ARRAY
Remove all array information except the values from an rpc-ARRAY structure.
Actually, only the type information is lost: the other components of the
complex XML structure are overhead.

=example
   if(my $a = $d->{array})
   {   my @v = rpcarray_values $a;
   }
=cut

sub rpcarray_values($)
{   my $rpca = shift;
    my @v;
    foreach ( @{$rpca->{data}{value} || []} )
    {   my ($type, $value) = %$_;
        push @v, $value;
    }
    @v;
}

=function rpcarray_from $type, LIST
Construct an rpc-array structure from a LIST of values. These values must
all have the same type.

=example
  my $d = rpcarray_from int => @a;
=cut

sub rpcarray_from($@)
{   my $type = shift;
    my @values = map { +{$type => $_} } @_;
    +{array => {data => {value => \@values}}};
}

=section Faults

=function fault_code $data
In LIST context, it returns both the integer faultCode as the
corresponding faultString.  In SCALAR context, only the code.

When the faultCode is C<0>, the value of C<-1> will be returned.
Some servers (like ExistDB 1.4) accidentally forget to set a
good numeric value.

=example
   if(my $f = $d->{fault})
   {    my ($rc, $rcmsg) = fault_code $f;
        my $rc = fault_code $f;
   }
=cut

sub fault_code($)
{   my $h  = struct_to_hash shift->{value}{struct};
    my $fc = $h->{faultCode} || -1;
    wantarray ? ($fc, $h->{faultString}) : $fc;
}

=function fault_from CODE, STRING
Construct a fault structure from an error code and the related error $string.

=example
   my $d = fault_from 42,'no answer';
=cut

sub fault_from($$)
{   my ($rc, $msg) = @_;
    my @rows = ([faultCode => int => $rc], [faultString => string => $msg]);
    +{fault => {value => struct_from_rows(@rows)}};
}

1;
