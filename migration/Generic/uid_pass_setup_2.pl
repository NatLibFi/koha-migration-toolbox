#!/usr/bin/perl
#---------------------------------
# Copyright 2010 ByWater Solutions
#
#---------------------------------
#
# -D Ruth Bavousett
#
#---------------------------------

use warnings;
use Getopt::Long;
use Text::CSV;
use C4::Context;
use C4::Members;
$|=1;
$debug=0;
$doo_eet=0;

GetOptions(
    'update'     => \$doo_eet,
    'debug'      => \$debug,
);

#if (($infile_name eq '')){
#   print "You're missing something.\n";
#   exit;
#}

my $dbh=C4::Context->dbh();
my $i=0;
my $find = $dbh->prepare("SELECT borrowernumber,cardnumber,firstname,surname FROM borrowers WHERE flags=0");
$find->execute();
while (my $row=$find->fetchrow_hashref()){
   $i++;
   print ".";
   print "\r$i" unless ($i % 100);
   my $pass = "";
   if (length $row->{cardnumber} >=4){
      $pass = substr $row->{cardnumber}, -4;
   }
   else{
      $pass = $row->{cardnumber};
   }
   my $uid = "";
   $uid = $row->{firstname}.'.'.$row->{surname};
   print "Changing $row->{'cardnumber'} to $uid / $pass\n" if ($debug);
   $doo_eet and C4::Members::ModMember(borrowernumber => $row->{'borrowernumber'}, 
                                       userid         => $uid,
                                       password       => $pass);
}

print "\n$i records updated.\n";
