#!/usr/bin/perl
#---------------------------------
# Copyright 2010 ByWater Solutions
#
#---------------------------------
#
# -Joy Nelson
#
#---------------------------------

use strict;
use warnings;
use Data::Dumper;
use Getopt::Long;
use Text::CSV_XS;
use Date::Calc qw(Add_Delta_Days);
use C4::Context;
use C4::Items;
use MARC::Record;
use MARC::Field;
$|=1;
my $debug=0;
my $doo_eet=0;

my $infile_name = "";
my $branch = "";

GetOptions(
    'in=s'            => \$infile_name,
    'branch=s'        => \$branch,
    'debug'           => \$debug,
    'update'          => \$doo_eet,
);

if ($infile_name eq '') {
  print "Something's missing.\n";
  exit;
}

my $csv = Text::CSV_XS->new( {binary=>1} );
open my $in,"<$infile_name";
my $i=0;
my %problem;
my %success;
my $dbh = C4::Context->dbh();
my $sth = $dbh->prepare("INSERT INTO old_issues (borrowernumber, itemnumber, returndate, branchcode) VALUES (?, ?, ?, 'HSGC')");
my $borr_sth = $dbh->prepare("SELECT borrowernumber FROM borrowers WHERE cardnumber=?");
my $item_sth = $dbh->prepare("SELECT itemnumber FROM items WHERE itemcallnumber=?");
my $dum = $csv->getline($in);

MAINLOOP:
while (my $line = $csv->getline($in))
{
   my @data = @$line;
   $i++;
   print ".";
   print "\r$i" unless $i % 100;
   $item_sth->execute($data[12]);
   my $db_item_fetch=$item_sth->fetchrow_hashref();
   my $itemnum = $db_item_fetch->{'itemnumber'};
   if (!$itemnum )
      {
      $problem{'items not found'}++;
      print "item not found: $data[12] \n";
      next MAINLOOP;
      }
   if ($data[0] ne "") {
      $data[0] =~ s/ //g; 
      $borr_sth->execute($data[0]);
      my $db_borr_fetch=$borr_sth->fetchrow_hashref();
      my $borrnum=$db_borr_fetch->{'borrowernumber'};
      my $returndate = $data[10];
      if ($borrnum) 
         {
         $doo_eet and $sth->execute($borrnum,$itemnum,$returndate);
         $success{'items checked out to borrower'}++;
         }
      else 
         {
         $problem{'borrowers not found'}++;
         print "borrower not found: $data[0]\n";
         }
      }
}

close $in;

print "\n\n$i lines read.\n";
foreach my $kee (sort keys %success)
{
   print "$success{$kee} $kee\n";
}

print "\nProblems:\n";
foreach my $kee (sort keys %problem)
{
   print "$problem{$kee} $kee\n";
}
   
exit;

