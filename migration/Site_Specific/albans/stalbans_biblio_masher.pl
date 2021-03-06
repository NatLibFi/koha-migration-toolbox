#!/usr/bin/perl
#---------------------------------
# Copyright 2010 ByWater Solutions
#
#---------------------------------
#
# -D Ruth Bavousett
# -edited by Joy Nelson
#
#---------------------------------

use strict;
use warnings;
use Data::Dumper;
use Getopt::Long;
use Text::CSV_XS;
use MARC::File::USMARC;
use MARC::Record;
use MARC::Batch;
use MARC::Charset;
$|=1;
my $debug=0;

my $infile_name = "";
my $outfile_name = "";
my $branch = "";
my $branch_map_name = "";
my %branch_map;
my $shelfloc_map_name = "";
my %shelfloc_map;
my $itype_map_name = "";
my %itype_map;
my $type_code_map_name = "";
my $collcode_map_name = "";
my %collcode_map;
my $prefix_itype_map_name = "";
my %prefix_itype_map;
my $drop_noitem = 0;
my %note_map;
my $note_map_name = "";

GetOptions(
    'in=s'          => \$infile_name,
    'out=s'         => \$outfile_name,
    'branch=s'          => \$branch,
    'branch_map=s'      => \$branch_map_name,
    'shelfloc_map=s'    => \$shelfloc_map_name,
    'itype_map=s'       => \$itype_map_name,
    'collcode_map=s'    => \$collcode_map_name,
    'type_code_map=s'   => \$type_code_map_name,
    'prefix_itype_map=s' => \$prefix_itype_map_name,
    'note_map=s'    => \$note_map_name,
    'drop_noitem'   => \$drop_noitem,
    'debug'         => \$debug,
);

if (($infile_name eq '') || ($outfile_name eq '')){
  print "Something's missing.\n";
  exit;
}
#if (($branch eq '')){
#  print "Something's missing.\n";
#  exit;
#}

if ($branch_map_name){
   my $csv = Text::CSV_XS->new();
   open my $mapfile,"<$branch_map_name";
   while (my $row = $csv->getline($mapfile)){
      my @data = @$row;
      $branch_map{$data[0]} = $data[1];
   }
   close $mapfile;
}
 
if ($note_map_name){
   my $csv = Text::CSV_XS->new();
   open my $mapfile,"<$note_map_name";
   while (my $row = $csv->getline($mapfile)){
      my @data = @$row;
      $note_map{$data[0]} = $data[1];
   }
   close $mapfile;
}

if ($shelfloc_map_name){
   my $csv = Text::CSV_XS->new();
   open my $mapfile,"<$shelfloc_map_name";
   while (my $row = $csv->getline($mapfile)){
      my @data = @$row;
      $shelfloc_map{$data[0]} = $data[1];
   }
   close $mapfile;
}

if ($itype_map_name){
   my $csv = Text::CSV_XS->new();
   open my $mapfile,"<$itype_map_name";
   while (my $row = $csv->getline($mapfile)){
      my @data = @$row;
      $itype_map{$data[0]} = $data[1];
   }
   close $mapfile;
}

if ($collcode_map_name){
   my $csv = Text::CSV_XS->new();
   open my $mapfile,"<$collcode_map_name";
   while (my $row = $csv->getline($mapfile)){
      my @data = @$row;
      $collcode_map{$data[0]} = $data[1];
   }
   close $mapfile;
}

if ($prefix_itype_map_name){
   my $csv = Text::CSV_XS->new();
   open my $mapfile,"<$prefix_itype_map_name";
   while (my $row = $csv->getline($mapfile)){
      my @data = @$row;
      $prefix_itype_map{$data[0]} = $data[1];
   }
   close $mapfile;
}

if ($type_code_map_name){
   my $csv = Text::CSV_XS->new();
   open my $mapfile,"<$type_code_map_name";
   while (my $row = $csv->getline($mapfile)){
      my @data = @$row;
      $itype_map{$data[0]} = $data[1];
      $collcode_map{$data[0]} = $data[2];
   }
   close $mapfile;
}

my $infl = IO::File->new($infile_name);
my $batch = MARC::Batch->new('USMARC',$infl);
$batch->warnings_off();
$batch->strict_off();
my $iggy = MARC::Charset::ignore_errors(1);
my $setting = MARC::Charset::assume_encoding('marc8');
open my $outfl,">:utf8",$outfile_name;
my $i=0;
my $j=0;
my $written=0;
my $no_852=0;
my $bad_852=0;
my %branchcount;
my %itypecount;
my %loccount;
my %collcodecount;
my %itype_942count;

while () {
   last if ($debug and $i > 99);
   my $record = $batch->next();
   $i++;
   print ".";
   print "\r$i" unless $i % 100;
   if ($@){
      print "Bogusness skipped\n";
      next;
   }
   last unless ($record);

   if (!$record->field("852")){
       $no_852++;
       next if ($drop_noitem);  
       foreach my $dumpfield($record->field('9..')){
          $record->delete_field($dumpfield);
       }
       foreach my $dumpfield($record->field('852')){
          $record->delete_field($dumpfield);
       }
       print $outfl $record->as_usmarc();
       $written++;
       next;
   }
   
   my $price = 0;

   if ($record->subfield("350","a")){
      $price = $record->subfield("350","a");
      #$price =~ s/\D\.]//;
      $price =~ s/(\d+(\.[0-9]{2}))/$1/;
      $price =~ s/\$//g;
   }

   my %homebranch;
   my %holdbranch;
   my %itype;
   my %loc;
   my %collcode;
   my %acqdate;
   my %acqsource;
   my %seendate;
   my %item_hidden_note;
   my %itmprice;
   my %replprice;
   my %copynum;
   my %itemcall;
   my %itemnote;
   my %issues;
   my %enumchron;
   my $keeper_itype;
   my $keep_this_record=0;
   my %voldesc;
   my %volnum;

   foreach my $field ($record->field("852")){
      $j++;
      my $barcode;
      if ($field->subfield('p')){
         $barcode= $field->subfield('p');
      }
      else{
         $bad_852++;
         $barcode="AUTO".sprintf("%05d",$i)."-".$j;
      }

      $homebranch{$barcode} = $field->subfield('a');
      $holdbranch{$barcode} = $field->subfield('a');

      if ($field->subfield('z')) {
         $item_hidden_note{$barcode} = $field->subfield('z');
         if ( exists($note_map{$item_hidden_note{$barcode}}) ){
            $item_hidden_note{$barcode} = $note_map{$item_hidden_note{$barcode}};
         }
         else {
            $item_hidden_note{$barcode}="";
         }
       }

# This is parsing the 852h field for the parts and using the prefix to determine shelf location
      my $callnum;
      $callnum  = ($field->subfield('h')) || "";
      $callnum = "UNKNOWN" if ($callnum eq ""); 

      my ($begincall, $midcall) = split /\s+/, $callnum, 2;
      if ( $begincall =~ m/[A-Za-z]/i ) {
          if (exists($shelfloc_map{$begincall})){
            $loc{$barcode} = $shelfloc_map{$begincall};
            if ($midcall) { 
                if ( ($midcall eq 'JUV') || ($midcall eq 'PIC') ){
                  $loc{$barcode} = "YAREA" ;
                }
            }
        $loccount{$loc{$barcode}}++;
          }
       }
       elsif ( $begincall =~ m/[0-9]+/ ) {
            $loc{$barcode}="-AAREA";
         $loccount{$loc{$barcode}}++;
        }
       else { 
          $loc{$barcode} = "" ;
        }       

      $keeper_itype=$itype{$barcode};

#copynumber
      $copynum{$barcode} = $field->subfield('t');

#callnumber
      $itemcall{$barcode} = $field->subfield('h') || " ";
      $itemcall{$barcode} =~ s/^\s+//;    
      $itemcall{$barcode} =~ s/\s+$//;    
      $itemcall{$barcode} =~ s/\s+$//;    

#private note $xFUND
      if ($field->subfield('x') =~ m/FUND/ ) {
        $item_hidden_note{$barcode} = $field->subfield('x');
      }      

######852$xFSC@ parsing here.....
      my $newsubfield;
      my @newsubfield = split /\@/, $field->subfield('x');
      foreach $newsubfield(@newsubfield) {
       my $subsubfield = substr $newsubfield, 0,1;
       if ($subsubfield eq 'j') {
          $voldesc{$barcode} = substr $newsubfield, 1;    #declared voldesc as hash above
        }
       if ($subsubfield eq 'i') {
          $volnum{$barcode} = substr $newsubfield, 1;      #declared volnum as hash above
        }
       if ($subsubfield eq 'f') {
         $acqsource{$barcode} = substr $newsubfield, 1;
        }
       if ($subsubfield eq 'c') {
         my $year = substr $newsubfield,1,4;
         my $month = substr $newsubfield,5,2;
         my $day = substr $newsubfield,7,2;
         if ($month && $day && $year){
            $acqdate{$barcode} = sprintf "%4d-%02d-%02d",$year,$month,$day;
            }
        }

       if ($subsubfield eq 'a' ) {
           $itype{$barcode} = substr $newsubfield, 1;
         if ( exists($itype_map{$itype{$barcode}}) ){
            $itype{$barcode} = $itype_map{$itype{$barcode}};
         }
         else {
            $itype{$barcode}="UNKNOWN";
         }
        $keeper_itype = $itype{$barcode};
       }        

        # grab @j and @i for Volume #  goes in 952h
  	if ( $voldesc{$barcode} && $volnum{$barcode} ) {
        $enumchron{$barcode} = $voldesc{$barcode} . $volnum{$barcode};
        }
                 
  }  

#  852$x@parsing end.

#subfield $b is sublocation.  Checking for graphic novel and Transitional Shelf
      if ( ($field->subfield('b')) && ($field->subfield('b') =~ m/Graphic/ ) ) {
         $loc{$barcode} = '-GN';
         $loccount{$loc{$barcode}}++;
      }
      if ( ($field->subfield('b')) && ($field->subfield('b') =~ m/Transitional/ ) ) {
         $loc{$barcode} = 'TRAN';
         $loccount{$loc{$barcode}}++;
      }

#fix for Periodicals and BAG callnumbers
       if ( $itemcall{$barcode} =~ m/Magazine/ ) {
           $itype{$barcode} = "PER";
           $keeper_itype = "PER";
       }
       if ( $itemcall{$barcode} =~ m/BAG/ ) {
           $itype{$barcode} = "EDK";
           $keeper_itype = "EDK";
       }


      my $thisprice=0;
      if ($field->subfield('9')){
         $thisprice = $field->subfield('9');
         $thisprice =~ s/(\d+(\.[0-9]{2}))/$1/;
         $thisprice =~ s/\$//g;
         $thisprice =~ s/p//g;
      }
      if (!$thisprice){
         $itmprice{$barcode} = $price if ($price);
         $replprice{$barcode} = $price if ($price);
      }
      else {
         $itmprice{$barcode} = $thisprice;
         my $replaceprice = $thisprice;
         $replprice{$barcode} =  $replaceprice;
      }

}

#end 852 loop


   foreach my $dumpfield($record->field('9..')){
      $record->delete_field($dumpfield);
   }
   foreach my $dumpfield($record->field('852')){
      $record->delete_field($dumpfield);
   }
   if ($keeper_itype){
      my $tag942=MARC::Field->new("942"," "," ", "c" => $keeper_itype);
      $record->insert_grouped_field($tag942);
      if ($keeper_itype ne 'DUMP'){
         $itype_942count{$keeper_itype}++;
         $keep_this_record=1;
      }
   }

   foreach my $key (sort keys %homebranch){
      if ($itype{$key} ne 'DUMP'){
         $itypecount{$itype{$key}}++;
         my $itmtag=MARC::Field->new("952"," "," ",
           "p" => $key,
           "a" => $homebranch{$key},
           "b" => $holdbranch{$key},
           "o" => $itemcall{$key},
           "y" => $itype{$key},
           "g" => $itmprice{$key},
           "v" => $replprice{$key},
           "2" => "ddc",
         );
         
         $itmtag->update( "c" => $loc{$key} ) if ($loc{$key});
         $itmtag->update( "d" => $acqdate{$key} ) if ($acqdate{$key});
         $itmtag->update( "e" => $acqsource{$key} ) if ($acqsource{$key});
         $itmtag->update( "r" => $seendate{$key} ) if ($seendate{$key});
         $itmtag->update( "x" => $item_hidden_note{$key} ) if ($item_hidden_note{$key});
         $itmtag->update( "8" => $collcode{$key} ) if ($collcode{$key});
         $itmtag->update( "t" => $copynum{$key} ) if ($copynum{$key});
         $itmtag->update( "z" => $itemnote{$key} ) if ($itemnote{$key});
         $itmtag->update( "l" => $issues{$key} ) if ($issues{$key});
         $itmtag->update( "h" => $enumchron{$key} ) if ($enumchron{$key});

         $record->insert_grouped_field($itmtag);
         $keep_this_record=1;
      }
   }

   if ($keep_this_record){
      print $outfl $record->as_usmarc();
      $written++;
   }
}
close $infl;
close $outfl;

open my $codes,">","biblio_codes.sql";
print $codes "# Branches\n";
foreach my $kee (sort keys %branchcount){
   print $codes "INSERT INTO branches (branchcode,branchname) VALUES ('$kee','$kee');\n";
}
print $codes "# Locations\n";
foreach my $kee (sort keys %loccount){
   if ($kee ne "NONE"){
      print $codes "INSERT INTO authorised_values (category,authorised_value,lib) VALUES ('LOC','$kee','$kee');\n";
   }
}
print $codes "# Item Types\n";
foreach my $kee (sort keys %itypecount){
   print $codes "INSERT INTO itemtypes (itemtype,description) VALUES ('$kee','$kee');\n";
}
print $codes "# Collection Codes\n";
foreach my $kee (sort keys %collcodecount){
   print $codes "INSERT INTO authorised_values (category,authorised_value,lib) VALUES ('CCODE','$kee','$kee');\n";
}
close $codes;

print "\n\n$i biblios read.\n$j items read.\n$written biblios written.\n";
print "$no_852 biblios with no 852.\n$bad_852 852s missing barcode, so codes autogenerated.\n";
print "\nBRANCHES:\n";
foreach my $kee (sort keys %branchcount){
   print $kee.":   ".$branchcount{$kee}."\n";
}
print "\nITEM TYPES:\n";
foreach my $kee (sort keys %itypecount){
   print $kee.":   ".$itypecount{$kee}."\n";
}
print "\nITEM TYPES (942):\n";
foreach my $kee (sort keys %itype_942count){
   print $kee.":   ".$itype_942count{$kee}."\n";
}
print "\nSHELVING LOCATIONS:\n";
foreach my $kee (sort keys %loccount){
   print $kee.":   ".$loccount{$kee}."\n";
}
print "\nCOLLECTION CODES\n";
foreach my $kee (sort keys %collcodecount){
   print $kee.":   ".$collcodecount{$kee}."\n";
}
print "\n";

