#!/usr/bin/perl
#---------------------------------
# Copyright 2012 ByWater Solutions
#
#---------------------------------
#
# -D Ruth Bavousett
#
# Modification log: 
# DRB 28 Jan 2012  (Revised for new extracts, multibranch capability)
# JEN 13 Mar 2012 (multiple changes specific to CIN) 
#---------------------------------
#
# EXPECTS:
#   -several CSV files extracted from Voyager
#
# DOES:
#   -nothing
#
# CREATES:
#   -Koha patron CSV
#
# REPORTS:
#   -number of records read from each input file
#   -number of records output

use autodie;
use strict;
use warnings;
use Carp;
use Data::Dumper;
use English qw( -no_match_vars );
use Getopt::Long;
use Readonly;
use Text::CSV_XS;
use C4::Context;
use DateTime;

local    $OUTPUT_AUTOFLUSH =  1;
Readonly my $NULL_STRING   => q{};

my $debug   = 0;
my $doo_eet = 0;
my $i       = 0;
my $j       = 0;
my $k       = 0;
my $written = 0;
my $problem = 0;

my $input_name_filename         = $NULL_STRING;
my $input_address_filename      = $NULL_STRING;
my $input_barcode_filename      = $NULL_STRING;
my $input_null_barcode_filename = $NULL_STRING;
my $input_notes_filename        = $NULL_STRING;
my $input_phone_filename        = $NULL_STRING;
my $input_stats_filename        = $NULL_STRING;
my $output_filename             = $NULL_STRING;
my $output_password_filename    = $NULL_STRING;
my $output_attributes_filename  = $NULL_STRING;
my $output_codes_filename       = $NULL_STRING;
my $fixed_branch                = 'UNKNOWN';
my $bad_titles                  = $NULL_STRING;
my $use_inst_id                 = 0;
my $branch_or_category          = 'branchcode';   #changed to branch
my $csv_delimiter               = 'comma';
my $tally_fields                = 'branchcode,categorycode';
my @static;
my @datamap_filenames;
my %datamap;
my @note_prefixes;
my %note_prefix;

GetOptions(
    'name=s'        => \$input_name_filename,
    'address=s'     => \$input_address_filename,
    'barcode=s'     => \$input_barcode_filename,
    'nullbar=s'     => \$input_null_barcode_filename,
    'notes=s'       => \$input_notes_filename,
    'phone=s'       => \$input_phone_filename,
    'stats=s'       => \$input_stats_filename,
    'out=s'         => \$output_filename,
    'password=s'    => \$output_password_filename,
    'attrib=s'      => \$output_attributes_filename,
    'codes=s'       => \$output_codes_filename,
    'bad_titles=s'  => \$bad_titles,
    'branch=s'      => \$fixed_branch,
    'use_inst_id'   => \$use_inst_id,
    'group=s'       => \$branch_or_category,
    'delimiter=s'   => \$csv_delimiter,
    'tally=s'       => \$tally_fields,
    'static=s'      => \@static,
    'map=s'         => \@datamap_filenames,
    'noteprefix=s'  => \@note_prefixes,
    'debug'         => \$debug,
);

my %delimiter = ( 'comma' => ',',
                  'tab'   => "\t",
                  'pipe'  => '|',
                );

for my $var ($input_name_filename,      $input_address_filename,     $input_barcode_filename, $input_null_barcode_filename,
             $input_notes_filename,     $input_phone_filename,       $input_stats_filename,   $output_filename,
             $output_password_filename, $output_attributes_filename) {
   croak ("You're missing something") if $var eq $NULL_STRING;
}

foreach my $map (@datamap_filenames) {
   my ($mapsub,$map_filename) = split (/:/,$map);
   my $csv = Text::CSV_XS->new();
   open my $mapfile,'<',$map_filename;
   while (my $row = $csv->getline($mapfile)) {
      my @data = @$row;
      $datamap{$mapsub}{$data[0]} = $data[1];
   }
   close $mapfile;
}

my @field_static;
foreach my $map (@static) {
   my ($field, $data) = $map =~ /^(.*?):(.*)$/;
   if (!$field || !$data) {
      croak ("--static=$map is ill-formed!\n");
   }
   push @field_static, {
      'field'  => $field,
      'data'   => $data,
   };
}

foreach my $map (@note_prefixes) {
   my ($field, $data) = $map =~ /^(.*?):(.*)$/;
   if (!$field || !$data) {
      croak ("--noteprefix=$map is ill-formed!\n");
   }
   $note_prefix{$field} = $data;
}

my %address_data_hash;
if ($input_address_filename ne $NULL_STRING) {
   print "Loading borrower address data into memory:\n";
   my $csv = Text::CSV_XS->new({ binary => 1, sep_char => $delimiter{$csv_delimiter} });
   open my $data_file,'<:utf8',$input_address_filename;
   $csv->column_names($csv->getline($data_file));
   while (my $line = $csv->getline_hr($data_file)) {
      $i++;
      print '.'    unless ($i % 10);
      print "\r$i" unless ($i % 100);
      push (@{$address_data_hash{$line->{PATRON_ID}}}, $line);
   }
   close $data_file;
   print "\n$i lines read.\n";
}

my %barcode_data_hash;
$i=0;
if ($input_barcode_filename ne $NULL_STRING) {
   print "Loading borrower barcode data into memory:\n";
   my $csv = Text::CSV_XS->new({ binary => 1, sep_char => $delimiter{$csv_delimiter} });
   open my $data_file,'<:utf8',$input_barcode_filename;
   $csv->column_names($csv->getline($data_file));
   while (my $line = $csv->getline_hr($data_file)) {
      $i++;
      print '.'    unless ($i % 10);
      print "\r$i" unless ($i % 100);
      push (@{$barcode_data_hash{$line->{PATRON_ID}}}, $line);
   }
   close $data_file;
   print "\n$i lines read.\n";
}

my %null_barcode_data_hash;
$i=0;
if ($input_null_barcode_filename ne $NULL_STRING) {
   print "Loading borrower null-barcode data into memory:\n";
   my $csv = Text::CSV_XS->new({ binary => 1, sep_char => $delimiter{$csv_delimiter} });
   open my $data_file,'<:utf8',$input_null_barcode_filename;
   $csv->column_names($csv->getline($data_file));
   while (my $line = $csv->getline_hr($data_file)) {
      $i++;
      print '.'    unless ($i % 10);
      print "\r$i" unless ($i % 100);
      push (@{$null_barcode_data_hash{$line->{PATRON_ID}}}, $line);
   }
   close $data_file;
   print "\n$i lines read.\n";
}

my %notes_data_hash;
if ($input_notes_filename ne $NULL_STRING) {
   print "Loading borrower notes data into memory:\n";
   my $csv = Text::CSV_XS->new({ binary => 1, sep_char => $delimiter{$csv_delimiter} });
   open my $data_file,'<:utf8',$input_notes_filename;
   $csv->column_names($csv->getline($data_file));
   while (my $line = $csv->getline_hr($data_file)) {
      $i++;
      print '.'    unless ($i % 10);
      print "\r$i" unless ($i % 100);
      push (@{$notes_data_hash{$line->{PATRON_ID}}}, $line);
   }
   close $data_file;
   print "\n$i lines read.\n";
}

my %phone_data_hash;
$i=0;
if ($input_phone_filename ne $NULL_STRING) {
   print "Loading borrower phone data into memory:\n";
   my $csv = Text::CSV_XS->new({ binary => 1, sep_char => $delimiter{$csv_delimiter} });
   open my $data_file,'<:utf8',$input_phone_filename;
   $csv->column_names($csv->getline($data_file));
   while (my $line = $csv->getline_hr($data_file)) {
      $i++;
      print '.'    unless ($i % 10);
      print "\r$i" unless ($i % 100);
      push (@{$phone_data_hash{$line->{PATRON_ID}}}, $line);
   }
   close $data_file;
   print "\n$i lines read.\n";
}

my %stats_data_hash;
$i=0;
if ($input_stats_filename ne $NULL_STRING) {
   print "Loading borrower stats data into memory:\n";
   my $csv = Text::CSV_XS->new({ binary => 1, sep_char => $delimiter{$csv_delimiter} });
   open my $data_file,'<:utf8',$input_stats_filename;
   $csv->column_names($csv->getline($data_file));
   while (my $line = $csv->getline_hr($data_file)) {
      $i++;
      print '.'    unless ($i % 10);
      print "\r$i" unless ($i % 100);
      push (@{$stats_data_hash{$line->{PATRON_ID}}}, $line);
   }
   close $data_file;
   print "\n$i lines read.\n";
}

my @borrower_fields = qw /cardnumber          surname
                          firstname           title
                          othernames          initials
                          address             address2
                          city                state                zipcode  country
                          email
                          phone               mobile
                          fax                 emailpro
                          phonepro            B_streetnumber
                          B_streettype        B_address
                          B_address2          B_city               B_state
                          B_zipcode           B_country
                          B_email             B_phone
                          dateofbirth         branchcode
                          categorycode        dateenrolled
                          dateexpiry          gonenoaddress
                          lost                debarred
                          contactname         contactfirstname
                          contacttitle        guarantorid
                          borrowernotes       relationship
                          ethnicity           ethnotes
                          sex                
                          flags               userid
                          opacnote            contactnote
                          sort1               sort2
                          altcontactfirstname altcontactsurname
                          altcontactaddress1  altcontactaddress2
                          altcontactaddress3  altcontactzipcode
                          altcontactcountry   altcontactphone
                          smsalertnumber      privacy/;

my %allowed_titles;
for my $title (split /\|/, C4::Context->preference('BorrowersTitles')) {
   my $title_match = uc $title;
   $title_match =~ s/\.$//;
   $allowed_titles{$title_match} = $title;
}

my %tally;
my $no_barcode=0;
$i=0;
my $incoming_date;

my $csv=Text::CSV_XS->new({ binary => 1 });
open my $input_file,'<:utf8',$input_name_filename;
$csv->column_names($csv->getline($input_file));

open my $output_file,'>:utf8',$output_filename;
for my $k (0..scalar(@borrower_fields)-1){
   print {$output_file} $borrower_fields[$k].',';
}
print {$output_file} "\n";

open my $output_password_file,  '>:utf8',$output_password_filename;
open my $output_attributes_file,'>:utf8',$output_attributes_filename;

RECORD:
while (my $row=$csv->getline_hr($input_file)){
   last RECORD if ($debug and $i>10);
   $i++;
   print '.'    unless ($i % 10);
   print "\r$i" unless ($i % 100);

   my %this_borrower;
   my $addedcode;

   foreach my $map (@field_static) {
      $this_borrower{$map->{'field'}} = $map->{'data'};
   }
 
   $this_borrower{sort1}         = $row->{PATRON_ID};
   $this_borrower{surname}       = $row->{LAST_NAME};
   $this_borrower{firstname}     = $row->{FIRST_NAME};
   $this_borrower{firstname}    .= $row->{MIDDLE_NAME} ne $NULL_STRING ? ' '.$row->{MIDDLE_NAME} : $NULL_STRING;

   my $tmp_title = uc $row->{TITLE};
   $tmp_title =~ s/\s+$//;
   $tmp_title =~ s/\.$//;
   if (exists $allowed_titles{$tmp_title}) {
      $this_borrower{title}      = $allowed_titles{$tmp_title};
   }
   elsif ($bad_titles ne $NULL_STRING) {
      $this_borrower{$bad_titles} = $row->{TITLE};
   }
   
   $this_borrower{dateenrolled} = _process_date($row->{REGISTRATION_DATE}) || $NULL_STRING;
#  $this_borrower{dateexpiry}   = _process_date($row->{EXPIRE_DATE})       || $NULL_STRING;

#  CIN wants to compare the expiration date to set new ones.  
    my $today = DateTime->now( time_zone => 'America/Chicago' );
    if ($row->{EXPIRE_DATE} eq $NULL_STRING) {
        $this_borrower{dateexpiry} = $today->ymd;
    }

    my $today_future = $today->add(years=>2);

    if ($row->{EXPIRE_DATE}) { 
        $incoming_date = _process_date2($row->{EXPIRE_DATE});
        if (DateTime->compare( $incoming_date, $today_future ) > 0) {
            $this_borrower{dateexpiry} = $today_future->ymd;
        }
        else {
            $this_borrower{dateexpiry} = _process_date($row->{EXPIRE_DATE});
        }
    }
#reset the today value for setting other patrons to expire.
   $today = DateTime->now( time_zone => 'America/Chicago' );;

   $this_borrower{cardnumber}   = $NULL_STRING; 
   if ($use_inst_id){
      $this_borrower{cardnumber}   = $row->{INSTITUTION_ID};
   }
   $this_borrower{sort2}        = $row->{INSTITUTION_ID};

# if patron_name_desc is Institutional then category is INST
   if ($row->{PATRON_NAME_DESC} eq 'Institutional') {
     $this_borrower{categorycode} = 'INST';
   }

   my $matchpoint = $row->{PATRON_ID};

   my @address_matches;
   foreach (@{$address_data_hash{$matchpoint}}){
      push (@address_matches, $_);
   }
   my @barcode_matches;
   foreach (@{$barcode_data_hash{$matchpoint}}){
      push (@barcode_matches, $_);
   }
   my @null_barcode_matches;
   foreach (@{$null_barcode_data_hash{$matchpoint}}){
      push (@null_barcode_matches, $_);
   }
   my @notes_matches;
   foreach (@{$notes_data_hash{$matchpoint}}){
      push (@notes_matches, $_);
   }
   my @phone_matches;
   foreach (@{$phone_data_hash{$matchpoint}}){
      push (@phone_matches, $_);
   }
   my @stats_matches;
   foreach (@{$stats_data_hash{$matchpoint}}){
      push (@stats_matches, $_);
   }
# for CIN need to make addresstype2 the Address and type1 the alternate address:
# this manipulation only affects .02% of their patrons
# if no type 2 then use type 1 for address field
# move all address_line2,3,4,5 to notes and flag address as bad.

#initialize the borrowernotes
$this_borrower{borrowernotes} = $NULL_STRING;

ADDRESS_MATCH:
   foreach my $match (@address_matches) {

      if ($match->{ADDRESS_TYPE} == 1){
         $this_borrower{B_address}     = $match->{ADDRESS_LINE1};
         $this_borrower{B_city}        = $match->{CITY};
         $this_borrower{B_state}       = $match->{STATE_PROVINCE};
         $this_borrower{B_zipcode}     = $match->{ZIP_POSTAL};
         $this_borrower{B_country}     = $match->{COUNTRY};
         $this_borrower{gonenoaddress} = '';
         if ($match->{ADDRESS_LINE1} eq '0' 
             || $match->{CITY} eq '0' 
             || $match->{STATE_PROVINCE} eq '0' 
             || $match->{ZIP_POSTAL} eq '0'
             || $match->{ADDRESS_LINE1} eq '00'
             || $match->{CITY} eq '00'
             || $match->{STATE_PROVINCE} eq '00'
             || $match->{ZIP_POSTAL} eq '00'
             || $match->{CITY} eq $NULL_STRING 
             || $match->{STATE_PROVINCE} eq $NULL_STRING 
             || $match->{ZIP_POSTAL} eq $NULL_STRING ) {       
            $this_borrower{gonenoaddress} =1;
            $this_borrower{borrowernotes} = $this_borrower{borrowernotes}.' *Migration* Patron expired due to issue with address: '.$match->{ADDRESS_LINE2}.' '.$match->{ADDRESS_LINE3}.' '.$match->{ADDRESS_LINE4}.' '.$match->{ADDRESS_LINE5};
            if (DateTime->compare( $incoming_date,$today) >0) {
              $this_borrower{dateexpiry} = $today->ymd;
            }
          }

         if ($match->{ADDRESS_LINE2} ne ''
             || $match->{ADDRESS_LINE3} ne ''
             || $match->{ADDRESS_LINE4} ne ''
             || $match->{ADDRESS_LINE5} ne '' ){
            $this_borrower{borrowernotes} = $this_borrower{borrowernotes}.' Addresslines2-5:'.$match->{ADDRESS_LINE2}.' '.$match->{ADDRESS_LINE3}.' '.$match->{ADDRESS_LINE4}.' '.$match->{ADDRESS_LINE5};
            $this_borrower{gonenoaddress} = 1;

         }
         next ADDRESS_MATCH;
      }

      if ($match->{ADDRESS_TYPE} == 2){
         $this_borrower{address}  = $match->{ADDRESS_LINE1};
         $this_borrower{city}    = $match->{CITY};
         $this_borrower{state}   = $match->{STATE_PROVINCE};
         $this_borrower{zipcode} = $match->{ZIP_POSTAL};
         $this_borrower{country} = $match->{COUNTRY};
         $this_borrower{gonenoaddress} = '';

        if ($match->{ADDRESS_LINE1} eq '0'
             || $match->{CITY} eq '0'
             || $match->{STATE_PROVINCE} eq '0'
             || $match->{ZIP_POSTAL} eq '0'
             || $match->{ADDRESS_LINE1} eq '00'
             || $match->{CITY} eq '00'
             || $match->{STATE_PROVINCE} eq '00'
             || $match->{ZIP_POSTAL} eq '00'
             || $match->{CITY} eq $NULL_STRING
             || $match->{STATE_PROVINCE} eq $NULL_STRING
             || $match->{ZIP_POSTAL} eq $NULL_STRING) {
            $this_borrower{borrowernotes} = $this_borrower{borrowernotes}.' *Migration* Patron expired due to issue with address: '.$match->{ADDRESS_LINE2}.' '.$match->{ADDRESS_LINE3}.' '.$match->{ADDRESS_LINE4}.' '.$match->{ADDRESS_LINE5};

            if (DateTime->compare( $incoming_date,$today) >0) {
              $this_borrower{dateexpiry} = $today->ymd;
            }
         }

         if ($match->{ADDRESS_LINE2} ne ''
             || $match->{ADDRESS_LINE3} ne ''
             || $match->{ADDRESS_LINE4} ne ''
             || $match->{ADDRESS_LINE5} ne '' ){
            $this_borrower{borrowernotes} = $this_borrower{borrowernotes}.' Addresslines2-5:'.$match->{ADDRESS_LINE2}.' '.$match->{ADDRESS_LINE3}.' '.$match->{ADDRESS_LINE4}.' '.$match->{ADDRESS_LINE5};
            $this_borrower{gonenoaddress} = 1;
         }
         next ADDRESS_MATCH;
      }

      if ($match->{ADDRESS_TYPE} == 3){
         $this_borrower{email} = $match->{ADDRESS_LINE1};

         next ADDRESS_MATCH;
      }
   }

#if no type 2 address then address, city,state, zip are blank...assign b_ values to them.
if (!$this_borrower{address}){
    $this_borrower{address} = $this_borrower{B_address};
    $this_borrower{city}    = $this_borrower{B_city};
    $this_borrower{state}   = $this_borrower{B_state};
    $this_borrower{zipcode} = $this_borrower{B_zipcode};
} 

# gets extended attributes and sex and initial category code
STAT_MATCH:
   foreach my $match(@stats_matches) {
      if (exists $datamap{stat}{$match->{PATRON_STAT_CODE}}) {
         foreach my $map (split /~/,$datamap{stat}{$match->{PATRON_STAT_CODE}}) {
            my ($field,$value) = split /:/,$map;
            if ( $field eq lc $field)  {
               $this_borrower{$field} = $value;
            }
            else {
               $addedcode .= ','.$field.':'.$value;
            }
         }
      }
   }

BARCODE_MATCH:
   foreach my $match (@barcode_matches) {

      if (!$use_inst_id){
         $this_borrower{cardnumber} = $match->{PATRON_BARCODE};
      }

      if ($match->{BARCODE_STATUS} != 1) {
         $this_borrower{lost} = 1;
      }
      if ($match->{PATRON_GROUP_NAME} eq 'NT'){
         if (($this_borrower{categorycode}) && ($this_borrower{categorycode} eq 'ADULT')) {
           $this_borrower{categorycode}='ADULTB';
         }
         if (($this_borrower{categorycode}) && ($this_borrower{categorycode} eq 'MINOR')) {
           $this_borrower{categorycode}='MINORB';
         }
      }
      if ($match->{PATRON_GROUP_NAME} eq 'TP'){
         if (($this_borrower{categorycode}) && ($this_borrower{categorycode} eq 'ADULT')) {
           $this_borrower{categorycode}='ADULTTP';
         }
         if  (($this_borrower{categorycode}) &&  ($this_borrower{categorycode} eq 'MINOR')) {
           $this_borrower{categorycode}='MINORTP';
         }
      }

      $this_borrower{$branch_or_category} = $match->{PATRON_GROUP_NAME};
   }

   if (!exists $this_borrower{$branch_or_category}){
NULL_BARCODE_MATCH:
      foreach my $match (@null_barcode_matches) {
         next NULL_BARCODE_MATCH if ($match->{BARCODE_STATUS} != 1);
         $this_borrower{$branch_or_category} = $match->{PATRON_GROUP_NAME};
      }
   }

# moved this to beginning as it does not wipe out previous notes when used.
#   $this_borrower{borrowernotes} = $NULL_STRING;
NOTES_MATCH:
   foreach my $match(@notes_matches) {
      if ($match->{NOTE_TYPE} && exists $note_prefix{$match->{NOTE_TYPE}}) {
         $match->{NOTE} = $note_prefix{$match->{NOTE_TYPE}} . $match->{NOTE};
      }
      $match->{NOTE} =~ s///g;
      $match->{NOTE} =~ s/\n/\\n/g;
      $this_borrower{borrowernotes} .= ' | '.$match->{NOTE};
   }

PHONE_MATCH:
   foreach my $match(@phone_matches) {
      if ($match->{PHONE_DESC} eq 'Primary') {
         $this_borrower{phone} = $match->{PHONE_NUMBER};
      }
      if ($match->{PHONE_DESC} eq 'Other') {
         $this_borrower{phonepro} = $match->{PHONE_NUMBER};
      }
      if ($match->{PHONE_DESC} eq 'Fax') {
         $this_borrower{fax} = $match->{PHONE_NUMBER};
      }
      if ($match->{PHONE_DESC} eq 'Mobile') {
         $this_borrower{mobile} = $match->{PHONE_NUMBER};
      }
   }

   if ($this_borrower{cardnumber} eq $NULL_STRING) {
      $this_borrower{cardnumber} = sprintf "TEMP%d",$this_borrower{sort1};
      $no_barcode++;
   }

   $this_borrower{userid}        = $this_borrower{cardnumber};
   $this_borrower{password}      = uc $this_borrower{surname};
# CIN wants surname as password
#   $this_borrower{password}      = substr $this_borrower{cardnumber},-4;

#CIN wants MINORB as default category
   if (!$this_borrower{categorycode}){
      $this_borrower{categorycode} = 'MINORB';
   }
   
   if (!$this_borrower{branchcode}){
      $this_borrower{branchcode}    = $fixed_branch;
   }

   for my $tag (keys %this_borrower) {
      $this_borrower{$tag} =~ s/^\s+//;
      $this_borrower{$tag} =~ s/^\| //;
      my $oldval = $this_borrower{$tag};
      if ($datamap{$tag}{$oldval}) {
         $this_borrower{$tag} = $datamap{$tag}{$oldval};
         if ($datamap{$tag}{$oldval} eq 'NULL') {
            delete $this_borrower{$tag};
         }
      }
   }

   foreach my $sub (split /,/, $tally_fields){
      if (exists $this_borrower{$sub}){
         $tally{$sub}{$this_borrower{$sub}}++;
      }
   }

   $debug and print Dumper(%this_borrower);
   for my $j (0..scalar(@borrower_fields)-1){
      if ($this_borrower{$borrower_fields[$j]}){
         $this_borrower{$borrower_fields[$j]} =~ s/\"/'/g;
         if ($this_borrower{$borrower_fields[$j]} =~ /,/){
            print {$output_file} '"'.$this_borrower{$borrower_fields[$j]}.'"';
         }
         else{
            print {$output_file} $this_borrower{$borrower_fields[$j]};
         }
      }
      print {$output_file} ',';
   }
   print {$output_file} "\n";

   if (exists $this_borrower{password}) {
      print {$output_password_file} "$this_borrower{cardnumber},$this_borrower{password}\n";
   }
   
   if ($addedcode){
      $addedcode =~ s/^,//;
      print {$output_attributes_file} $this_borrower{cardnumber}.',"'.$addedcode.'"'."\n";
   }

   $written++;
}
close $input_file;
close $output_file;
close $output_password_file;
close $output_attributes_file;

print "\n\n$i lines read.\n$written borrowers written.\n$no_barcode with no barcode.\n";

open my $codes_file,'>',$output_codes_filename;
foreach my $kee (sort keys %{ $tally{branchcode} } ){
   print {$codes_file} "REPLACE INTO branches (branchcode,branchname) VALUES ('$kee','$kee');\n";
}
foreach my $kee (sort keys %{ $tally{categorycode} } ){
   if (!$tally{a}{$kee}) {
      print {$codes_file} "REPLACE INTO categories (categorycode,description) VALUES ('$kee','$kee');\n";
   }
}
close $codes_file;

print "\nTally results:\n\n";

foreach my $sub (split /,/,$tally_fields) {
   print "\nSubfield $sub:\n";
   foreach my $kee (sort keys %{ $tally{$sub} }) {
      print $kee.':  '.$tally{$sub}{$kee}."\n";
   }
}

exit;

#dates are coming in four digit year -
sub _process_date {
   my $datein = shift;
   return undef if !$datein;
   return undef if $datein eq $NULL_STRING;
   my ($month,$day,$year) = $datein =~ /(\d+).(\d+).(\d+)/;
   my $data;
   if ($month && $day && $year) {
#      my @time = localtime();
#      my $thisyear = $time[5]+1900;
#      $thisyear = substr($thisyear,2,2);
#      if ($year < $thisyear) {
#        $year += 2000;
#      }
#      elsif ($year > 50) {
#        $year += 1900;
#      }
#      else {
#        $year += 2000;
#      }
      return sprintf "%4d-%02d-%02d",$year,$month,$day;
      if ($data eq "0000-00-00") {
        return undef;
      }
   }
   else {
      return undef;
   }
}

sub _process_date2 {
   my $datein = shift;
   return undef if !$datein;
   return undef if $datein eq $NULL_STRING;
   my ($month,$day,$year) = $datein =~ /(\d+).(\d+).(\d+)/;
   if ($month && $day && $year) {
#      my @time = localtime();
#      my $thisyear = $time[5]+1900;
#      $thisyear = substr($thisyear,2,2);
#      if ($year < $thisyear) {
#        $year += 2000;
#      }
#      elsif ($year > 50) {
#        $year += 1900;
#      }
#      else {
#       $year += 2000;
#      }
   return DateTime->new(year=>$year,month=>$month,day=>$day);
   }
   else {
      return undef;
   }
}

