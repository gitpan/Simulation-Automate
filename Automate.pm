package Simulation::Automate;

use vars qw( $VERSION );
$VERSION = "0.9.7";

#################################################################################
#                                                                              	#
#  Copyright (C) 2000,2002 Wim Vanderbauwhede. All rights reserved.             #
#  This program is free software; you can redistribute it and/or modify it      #
#  under the same terms as Perl itself.                                         #
#                                                                              	#
#################################################################################

#headers
#
#Main module for SynSim simulation automation tool.
#The first part creates the module Loops.pm based on the data file;	
#this module is then called via eval() and used by Simulation::Automate.pm 
#Loops calls &Automate::main() at every pass through the loops.
#
#$Id: Automate.pm,v 1.2 2003/09/04 09:53:25 wim Exp $
#


use sigtrap qw(die untrapped normal-signals
               stack-trace any error-signals); 
use strict;
use Cwd;
use Exporter;
use lib '.';
use Simulation::Automate::Remote;

@Simulation::Automate::ISA = qw(Exporter);
@Simulation::Automate::EXPORT = qw(
		     &synsim
		     &setup
		     &localinstall
                  );

#===============================================================================
sub synsim {
  my $remotehost=&check_for_remote_host();
  if($remotehost){
    &run_on_remote_host($remotehost)
  } else {
    &run_local(); # new name for sub synsim
  }
}
#===============================================================================
sub run_local {
my $datafile=shift||'synsim.data';

################################################################################
#
#                     Create  module Simulation::Automate::Loops.pm
#
################################################################################

my @flags=my ($batch,$interactive,$nosims,$plot,$verbose,$warn)=@{&preprocess_commandline($datafile)};
my $dataset=$datafile;
$dataset=~s/\.data//;
print STDERR "\nCreating Loops.pm...\n" if $verbose;

my $dataref=&allow_multiple_sims($datafile);
my $simref=&generate_loop_module($dataref,$dataset,\@flags);

################################################################################
#
#                     Do the actual simulations
#
################################################################################

&execute_loop($datafile,$dataset,$simref,\@flags) && do {
unlink "Loops_$dataset.pm";
};
print STDERR "\nFinished SynSim run for $dataset\n\n";
return 1;
}
#===============================================================================

################################################################################
##
##                    Subroutines
##
################################################################################

sub preprocess_commandline {
my $datafile=$_[0];
my ($batch,$interactive,$nosims,$plot,$verbose,$warn,$justplot)=(0,0,0,0,0,0,0);
my $default=1;
if(@ARGV) {
my $dtf=0;
    foreach(@ARGV) {
      if(/-f/){$dtf=1;next}
      if($dtf==1) {
	$_[0]=$_;$datafile=$_;$default=0;$dtf=0;
      }
      if(/-b/){$batch=1;next} 
      if(/-i/){$interactive=1;$plot=1;$verbose=1;next}
      if(/-N/){$nosims=1;next}
      if(/-p/){$plot=1;next}
      if(/-v/){$verbose=1;next}
      if(/-w/){$warn=1;next;}
      if(/-P/){$justplot=1;next}
      if(/-D/) {
	(not -d 'TEMPLATES') && mkdir 'TEMPLATES';
	(not -d 'TEMPLATES/SIMTYPES') && mkdir 'TEMPLATES/SIMTYPES';
	(not -d 'TEMPLATES/DEVTYPES') && mkdir 'TEMPLATES/DEVTYPES';
	(not -d 'SOURCES') && mkdir 'SOURCES';
	die "An empty directory structure has been created\n";
      }
      if(/-h|-\?/) { 
my $script=$0;
$script=~s/.*\///;
die <<"HELP";

The script must be executed in a subdirectory of the directory
containing the script.
This directory must contain at least a TEMPLATES/SIMTYPE subdir 
with the simulation templates, and a data file. See documentation for more information.

syntax: ./$script [-h -i -p -v -w -N -f datafile]

Possible switches:

none: defaults to -f $datafile
 -f [filename]: 'file input'. Expects a file containing info about simulation and device type.
 -i : interactive. Creates a plot on the screen after every iteration. Implies -p -v
 -p : plot.  
 -v : 'verbose'. Sends simulator output to STDOUT, otherwise to simlog file
 -w : 'warnings'. Show warnings for undefined variables.
 -N : 'No simulations'. Does only postprocessing
 -h, -? : this help
HELP
}
    } # foreach @ARGV

#test if the last argument might be the filename (if no -f flag)
if($default){
my $test=$ARGV[@ARGV-1];
if($test!~/^\-/) {
$datafile=$test;
$default=0;
$_[0]=$datafile;
}
}

    if($default) {
print STDERR "Assuming $datafile as input data filename\n" if $verbose;
}
    } else {
print STDERR "No command line arguments given. Assuming $datafile as input data filename\n" if $verbose;
}

if(not(-e "./TEMPLATES" && -d "./TEMPLATES" && -e "./$datafile")) {
die  "
The current directory must contain at least a TEMPLATES/SIMTYPE subdir with the simulation templates, and a data file. See documentation for more information.

If Simulation::Automate is installed locally, the current directory must be in the same directoy as the Simulation directory.

";
}
if($justplot){
#convenience function to plot results
chomp(my $simtype=`egrep ^SIMTYPE $datafile`);
$simtype=~s/^SIMTYPE\s*:\s*//;
$simtype=~s/\s*$//;
chomp(my $anatype=`egrep ^ANALYSIS_TEMPLATE $datafile`);
$anatype=~s/^ANALYSIS_TEMPLATE\s*:\s*//;
$anatype=~s/\s*$//;
$datafile=~s/\.data//;

chdir "${simtype}-$datafile";
system("ggv ${simtype}-$anatype.ps");
die "Done\n";
}
return [$batch,$interactive,$nosims,$plot,$verbose,$warn];
} #END of preprocess_commandline

#-------------------------------------------------------------------------------
#
# This subroutine takes a reference to %specific as generated by allow_multiple_sims($datafile) and passes it on to fill_data_hash_multi;
# It gets back %data, which contains the list of parameters and their value-list for every simtype
#

sub generate_loop_module {
my $specificref=shift; #this is the reference to %specific, the hash of arrays of data for each sim
my $dataset=shift;
my $flagsref=shift;
my ($batch,$interactive,$nosims,$plot,$verbose,$warn)=@{$flagsref};
my $dataref=&fill_data_hash_multi($specificref);
my %data=%{$dataref};
open(MOD,">Loops_$dataset.pm");

print MOD &strip(<<"ENDHEAD");
*package Loops_$dataset;
*#
*################################################################################
*# Author:           WV                                                         #
*# Date  : 21/11/2000;01/08/2002                                                #
*#                                                                              #
*# Module to support script for SynSim simulations.                             #
*# The subroutine in this module generates the loop to do multiple simulations. #
*# This module is generated by Simulation::Automate.pm                          #
*#                                                                              #
*################################################################################
*
*use sigtrap qw(die untrapped normal-signals
*               stack-trace any error-signals); 
*use strict;
*
*use FileHandle;
*use Exporter;
*
*\@Loops_${dataset}::ISA = qw(Exporter);
*\@Loops_${dataset}::EXPORT = qw(
ENDHEAD

foreach my $sim (keys %data) {
print MOD &strip(
"*			execute_${sim}_loop\n");
}
print MOD &strip('
*                  );
*
');

my @sims=();
foreach my $sim (keys %data) { 
my $title=$data{$sim}{TITLE};
delete $data{$sim}{TITLE};

#experimental
my $nruns=(exists $data{$sim}{NRUNS})?$data{$sim}{NRUNS}:1;
if($nruns>1) {
$data{$sim}{__NRUNS}=join(',',(1..$nruns));
#also, make sure the SWEEPVAR list is comma-separated
#$data{$sim}{$data{$sim}{SWEEPVAR}}=~s/;/,/g;
}
push @sims,$sim;
print MOD &strip(<<"ENDSUBHEAD");

*use lib '..','../..';
*#use Simulation::Automate::Main;
*use Simulation::Automate;
*use Simulation::Automate::PostProcessors;
*
*sub execute_${sim}_loop {
*my \$dataset=shift;
*my \$dirname=\"${sim}-\$dataset\";
*my \$flagsref=shift;
*my \$i=0;
*my \$returnvalue;
*my \$resheader='';
*my \%last=();
*my \%sweepeddata=();
*my \$v=$verbose;

ENDSUBHEAD

if($data{$sim}{'PREPROCESSOR'}) {
print MOD &strip('
*my $preprocref=\&Simulation::Automate::PostProcessors::'.$data{$sim}{'PREPROCESSOR'}.';
');
} else {
print MOD &strip('
*my $preprocref;
');
}

# TITLE is treated separately
print MOD &strip(
"*my \$TITLE = '$title';\n"
);
# define vars
 foreach my $par (sort keys %{$data{$sim}}) {
if ($data{$sim}{$par}!~/,/) { # if just one item
#WV21052003 support for "for..to..step.."-style lists
$data{$sim}{$par}=&expand_list($data{$sim}{$par});

$data{$sim}{$par}=~s/^\'//;
$data{$sim}{$par}=~s/\'$//;
print MOD &strip(
"*my \$${par} = '$data{$sim}{$par}';\n"
);
} 
  }
#assign common hash items
print MOD &strip(
"*my \%data=();\n"
);
print MOD &strip('
*	print STDERR "# SynSim configuration variables\n" if $v;
*	print STDERR "#","-" x 79,"\n#  TITLE : '.$title.'\n" if $v;
*	$resheader.= "# SynSim configuration variables\n";
*	$resheader.= "#"."-" x 79;
*	$resheader.= "\n#  TITLE : '.$title.'\n";
');
print MOD &strip(
"*\$data{TITLE}=\$TITLE;\n"
);
my $nsims=1;
my $prevkey='';
foreach my $par (sort keys %{$data{$sim}}) {
  if($par=~/^_/ && $prevkey!~/^_/) {
print MOD &strip('
*	print STDERR "#","-" x 79,"\n" if $v;
*	print STDERR "# Static parameters used in the simulation:\n" if $v;
*	print STDERR "#","-" x 79,"\n" if $v;
*	$resheader.= "#"."-" x 79;
*	$resheader.= "\n# Static parameters used in the simulation:\n";
*	$resheader.= "#"."-" x 79;
*	$resheader.= "\n";
');
  }

  if ($data{$sim}{$par}!~/,/) { # if just one item, or it might be a sweep
    if($data{$sim}{$par}=~/(\d+)\s*\.\.\s*(\d+)/) {
      my $b=$1;
      my $e=$2;
      my $patt="$b .. $e";
      $nsims=$e-$b+1;
      print MOD &strip(
"*my \@tmp$par=($patt);
*\$data{$par} = [\@tmp$par];
*print STDERR \"# $par = \$$par\\n\" if \$v;
*\$resheader.=  \"# $par = \$$par\\n\";
");

    } elsif($data{$sim}{$par}=~/;/) {
     
 my $tmp=$data{$sim}{$par};
      my $tmps=($tmp=~s/;/,/g);
      if($tmps>=$nsims){$nsims=$tmps+1}
      print MOD &strip(
"*my \@tmp$par=split(/;/,\$$par);
*\$data{$par} = [\@tmp$par];
*print STDERR \"# $par = \$$par\\n\" if \$v;
*\$resheader.= \"# $par = \$$par\\n\";
");
    } else {
      if($par=~/^_/) {
	print MOD &strip(
"*\$data{$par} = [\$$par];
*print STDERR \"# $par = \$$par\\n\" if \$v;
*\$resheader.= \"# $par = \$$par\\n\";
");
      } else {
	print MOD &strip(
"*\$data{$par} = \$$par; # no reason for array
*print STDERR \"#  $par : \$$par\\n\" if \$v; # no reason to print
*\$resheader.= \"#  $par : \$$par\\n\"; # no reason to print
");

      }
    }
  }
$prevkey=$par;
}

print MOD &strip(
"*my \$nsims=$nsims;\n"
);


foreach my $par (sort keys %{$data{$sim}}) {

  if ($data{$sim}{$par}=~/,/) { # if more than one item
#WV21052003 support for "for to step"-style lists
$data{$sim}{$par}=&expand_list($data{$sim}{$par});
my $parlist=$data{$sim}{$par};
$parlist=~s/,/ /g;
    print MOD &strip(
		     "*my \@${par}list = qw($parlist);
*\$last{$par}=\$${par}list[\@${par}list-1];
*foreach my \$${par} (\@${par}list) {\n"
		    );
  } 
}
print MOD &strip(
"*\$i++;
*open(RES,\">\$dirname\/${sim}_C\$i.res\")|| do {print STDERR \"Can\'t open \$dirname\/${sim}_\$i.res\" if \$v;};
");
print MOD &strip('
*	print STDERR "#","-" x 79,"\n" if $v;
*	print STDERR "# Parameters for simulation run $i:\n" if $v;
*	print RES $resheader;
*	print RES "#"."-" x 79,"\n";
*	print RES "# Parameters for simulation run $i:\n";
');


my $simtempl=$data{$sim}{SIMTYPE};
my $anatempl=$data{$sim}{ANALYSIS_TEMPLATE}||'NoAnalysisDefined';
my $subref=$anatempl;

print MOD &strip('
*my $resfilename="'.$sim.'-'.$anatempl.'";
');
foreach my $par (sort keys %{$data{$sim}}) {

  if ($data{$sim}{$par}=~/,/) { # if more than one item
    print MOD &strip(
		     "*\$data{$par} = [\$$par];
*\$sweepeddata{$par} = \$$par;
*\$resfilename.=\"-${par}-\$$par\";
*print STDERR \"# $par = \$$par\\n\" if \$v;
*print RES \"# $par = \$$par\\n\";
");
  }
}

#WV21042003: old, sweep loops internal
print MOD &strip(
"* close RES;
*\$resfilename.='.res';
*#NEW01072003#rename \"\$dirname\/${sim}_C\$i.res\",\"\$dirname\/\$resfilename\";
*my \$dataref = [\$nsims,\\\%data];
*\$returnvalue=&main(\$dataset,\$i,\$dataref,\$resfilename,\$flagsref);
*
");

##WV21042003: new, sweep loops external
#print MOD &strip(
#"* close RES;
#*my \$dataref = [\$nsims,\\\%data];
#*my \$nsims=&pre_run(\$dataset,\$i,\$dataref,\$flagsref);
#*foreach my \$simn (1..\$nsims) {
#*\$returnvalue=&run(\$nsims,\$simn);
#*}
#*\$returnvalue=&post_run(\$dataset,\$i,\$dataref,\$flagsref);
#*
#*
#");


print MOD &strip(<<"ENDPP");
*chdir \$dirname;
*my \$dataref1 = [\$nsims,\\\%data,\\\%sweepeddata,\\\%last];
*&Simulation::Automate::PostProcessors::$subref(\$dataset,\$i,\$dataref1,\$flagsref,\$returnvalue,\$preprocref);
*chdir '..';
ENDPP

foreach my $par (reverse sort keys %{$data{$sim}}) {
  if ($data{$sim}{$par}=~/,/) {
    print MOD &strip(
		     "*} #END of $par\n"
		    );
  }
}

print MOD &strip(<<"ENDPP");
*chdir \$dirname;
*my \$dataref2 = [\$nsims,\\\%data,\\\%sweepeddata,\\\%last];
*&Simulation::Automate::PostProcessors::$subref(\$dataset,\$i,\$dataref2,\$flagsref,1);
*chdir '..';
ENDPP

print MOD &strip(<<"ENDTAIL");
* return \$returnvalue;
*} #END of execute_${sim}_loop
ENDTAIL
$data{$sim}{TITLE}=$title;
} #END of loop over sims

close MOD;
print STDERR "...Done\n\n" if $verbose;

return \%data;
} #END of generate loop module

#-------------------------------------------------------------------------------
sub strip {
my $line=shift;
$line=~s/(^|\n)\*/$1/sg;
return $line;
}
#-------------------------------------------------------------------------------
#
# This subroutine takes a reference to %specific as generated by allow_multiple_sims($datafile)
# So  %multisimdata is actually %specific
# Then, it turns this into a hash of hashes:
# for every $sim, there's a hash with as key the parameter name and as value its value-list
# This is %data, which is returned to $dataref in  generate_loop_module()
# 
sub fill_data_hash_multi {
my $dataref=shift;
my %data=();
my %multisimdata=%$dataref;
foreach my $sim (keys %multisimdata) {

  foreach (@{$multisimdata{$sim}}){

  if(/^\s*_/) {

my @line=();#split(/\s*=\s*/,$_);
# changed to allow expressions with "=" 
my $line=$_;
($line=~s/^([A-Z0-9_]+)?\s*=\s*//)&&($line[0]=$1);
$line[1]=$line;
$line[1]=~s/\s*\,\s*/,/g;
$line[1]=~s/\s*\;\s*/;/g;
$data{$sim}{$line[0]}=$line[1];
} elsif (/:/) {
my @line=();#split(/\s*:\s*/,$_);
# changed to allow expressions with ":"
my $line=$_;
($line=~s/^([A-Z0-9_]+)?\s*\:\s*//)&&($line[0]=$1);
$line[1]=$line;
##strip leading _
#$line[0]=~s/^\s*_//;
#strip trailing spaces
$line[1]=~s/\s+$//;
$data{$sim}{$line[0]}=$line[1];

} #if
  } # foreach
}
return \%data;
} #END of fill_data_hash_multi

#-------------------------------------------------------------------------------
#
# this subroutine splits the datafile into a common part (@common) and a number
# of simtype-specific parts ( %specific{$simtype}); then, it pushes @common onto
# @{$specific{$simtype}} and returns \%specific
# So every key in %specific points to an array with all variables needed for that simtype
#
sub allow_multiple_sims {
my $datafile=shift;
my @sims=();
my $simpart=0;
my $simpatt='NOPATTERN';
my @common=();
my %specific=();
my $simtype='NOKEY';
my $skip=0;
open(DATA,"<$datafile")|| die "Can't open $datafile\n";

while(<DATA>) {

/^\s*\#/ && next;
/^\s*$/ && next;
chomp;
# allow include files for configuration variables
/INCL.*\s*:/ && do {
my $incl=$_;
$incl=~s/^.*\:\s*//;
$incl=~s/\s+$//;
my @incl=($incl=~/,/)?split(/\s*,\s*/,$incl):($incl);
foreach my $inclf (@incl) {
open(INCL,"<$inclf")|| die $!;
while(my $incl=<INCL>) {
$incl=~/^\s*\#/ && next;
$incl=~/^\s*$/ && next;
chomp $incl;
# only configuration variables in include files!
($incl=~/:/) && do {push @common,$incl};
}
close INCL;
}
}; # END of allow INCL files
#print STDERR "$_\n";
s/(\#.*)//;
s/[;,]\s*$//; # be tolerant
if(/SIMTYPE\s*:/) {
my $sims=$_;
(my $par,$simpatt)=split(/\s*:\s*/,$sims);
$simpatt=~s/\s*\,\s*/|/g;
$simpatt=~s/\s+//g;
@sims=split(/\|/,$simpatt);
$simpatt='('.$simpatt.')';
} elsif(/$simpatt/) {
$skip=0;
$simtype=$1;
$simpart=1
} elsif(/^\s*[a-zA-Z]/&&!/:/) {
$simpart=0;
$skip=1;
print STDERR "$_: Not present in simlist. Skipping data.\n";
}

if($simpart) {
push @{$specific{$simtype}},$_;
} elsif(!$skip) {
push @common,$_;
} else {
print STDERR "Skipped: $_\n" ;
}

} #while
close DATA;

foreach my $sim (@sims) {
push @{$specific{$sim}},@common;
}

return \%specific;
} #END of allow_multiple_sims
#-------------------------------------------------------------------------------
#
# this subroutine expands for-to-step lists in enumerated lists
#
sub expand_list {
my $list=shift;
my $sep=',';
($list=~/;/)&&($sep=';');
my @list=split(/\s*$sep\s*/,$list);
if(@list==3 && $list!~/[a-zA-Z]/) { # 
if(
(abs($list[0])<abs($list[1]))&&(abs($list[2])<abs($list[1]-$list[0]))
) { #it's a for-to-step list, expand it
my $start=$list[0];
my $stop=$list[1];
my $step=$list[2];
$list="$start";
my $i=$start;
#while($i*(abs($step)/$step)<$stop*(abs($step)/$step)){
while(("$i" ne "$stop") && (abs($i)-abs($stop))<=0) { #yes, strange, but Perl says 0.9>0.9 is true!
$i+=$step;
$list.="$sep$i";
}
}
}
return $list;
} # END of expand_list
#===============================================================================

sub execute_loop {
my $datafilename=shift;
my $dataset=shift;

require "./Loops_$dataset.pm";
#eval("
#use Loops_$dataset;
#");

my $simref=shift;
my @flags=@{shift(@_)};
my $nosims=$flags[2];
my $verbose=$flags[4];

foreach my $sim (sort keys %{$simref}) {
# extension for template files
my $templ=${$simref}{$sim}->{TEMPL}||'.templ';
my $dev=${$simref}{$sim}->{DEVTYPE}||'';

my $dirname= "${sim}-$dataset";

  if(-e $dirname && -d $dirname) {
    if ($nosims==0) {
print STDERR "\n# Removing old $dirname dir\n" if $verbose;
if ($verbose) {
print `rm -Rf $dirname`;
} else {
system("rm -Rf $dirname");
}
} else {
print STDERR "\n# Cleaning up $dirname dir\n" if $verbose;
if ($verbose) {
print `rm -f $dirname/$sim-*`;
print `rm -f $dirname/tmp*`;
} else {
system("rm -f $dirname/tmp*");
}
}
}

  if (not -e "TEMPLATES/SIMTYPES/$sim$templ" ) {
print STDERR "No templates for simulation $sim. Skipped.\n" if $verbose;
next;
} else {

mkdir $dirname, 0755;
#WV1710: new organisation, allow both devices & simulations
#old:
#system("cp TEMPLATES/SIMTYPES/$sim.* $dirname");
#system("cp TEMPLATES/DEVTYPES/$sim.* $dirname");
#new:
if (-e "TEMPLATES/SIMTYPES/$sim$templ") {
system("cp TEMPLATES/SIMTYPES/$sim$templ $dirname");
} else {
die "There's no simulation template for $sim in TEMPLATES/SIMTYPES\n";
}
if($dev){
if (-e "TEMPLATES/DEVTYPES/$dev$templ") {
system("cp TEMPLATES/DEVTYPES/$dev$templ $dirname");
} else {
print STDERR "No device template for $dev in TEMPLATES/DEVTYPES.\n" if $verbose;
}
}
# any file with this pattern is copied to the rundir.
if (-d "SOURCES") {
  if(<SOURCES/$sim*>){
system("cp SOURCES/$sim* $dirname");
}
} 
}
print STDERR "#" x 80,"\n" if $verbose;
print STDERR "#\n" if $verbose;
print STDERR "# Simulation type: $sim, device dir ".`pwd`."#\n" if $verbose;
print STDERR "#" x 80,"\n" if $verbose;

eval('&Loops_'.$dataset.'::execute_'.$sim.'_loop($dataset,\@flags);');

} #sims
return 1;
} #END of &execute_loop
#==============================================================================
#Routines to support script for simulation automation.
#The function &main() is called from the innermost loop of
#Loops_*.pm
push @Simulation::Automate::EXPORT, qw(
		     main
		     pre_run
		     run
		     post_run					
);

use  Simulation::Automate::Analysis;

##################################################################################
my $simpid=undef; 

sub main {

use Cwd;
#&main($dataset,$i,$dataref,$resfilename,$flagsref);
my $dataset=shift; 
my $count=shift;
my $dataref=shift;
my $resfile=shift;
my $flagsref=shift;

my ($batch,$interactive,$nosims,$plot,$verbose,$warn)=@{$flagsref};

(my $nsims, my $simdataref)=@{$dataref};

print STDERR '#',"-" x 79, "\n" if $verbose;## Simulation run $count\n";

my %simdata=%{$simdataref};

my @results=();
my $command=$simdata{COMMAND}||'perl inputfile outputfile'; 

my $output_filter_pattern=$simdata{OUTPUT_FILTER_PATTERN}|| '.*';
my $simtype=$simdata{SIMTYPE}||'';
my $dirname= "${simtype}-$dataset";

my $devtype=$simdata{DEVTYPE}||'';
my $simtitle=$simdata{TITLE};
my @sweepvarnames=();
foreach my $key (keys %simdata) {
($key!~/^_/) && next;
($simtitle=~/$key/) && do {
$simtitle=~s/$key/$key:$simdata{$key}->[0]/;
};
my $ndata=@{$simdata{$key}};
if($ndata>1) {
push @sweepvarnames,$key;
  }
}
my $title="#$simtitle\n"||"#$devtype $simtype simulation\n";
my $ext=$simdata{TEMPL}||'.templ';
my $extin=$simdata{EXT}||'.pl';
my $workingdir =cwd();
chdir  "$workingdir/$dirname";

## INPUT FILE CREATION

foreach my $simn (1..$nsims) {
  if($nsims==1){$simn=''} else {
    print STDERR "# Subrun $simn of $nsims: " if $verbose;
    foreach my $sweepvarname(@sweepvarnames){
      print STDERR " $sweepvarname = ",$simdata{$sweepvarname}->[$simn-1] if $verbose;
    }
    print STDERR " \n" if $verbose;
  }
  my $inputfile= "${simtype}_${simn}$extin";
  my $outputfile= "${simtype}_C${count}_${simn}.out";
  my $commandline=$command;
  $commandline=~s/inputfile/$inputfile/ig;
  $commandline=~s/outputfile/$outputfile/ig;
  
  open (NEW, ">$inputfile");
  print NEW ("$title");

  foreach my $type ($devtype,$simtype) {
    if($type) {
      my $nsim=($simn eq '')?0:$simn;
      &gen_sim_script ($nsim-1,"$simtype$ext",\%simdata,\*NEW,$dataset,$warn);
      print NEW ("\n");
    }
  } # device and simulation templates
  close (NEW);
  
  if($nosims==0) {
    if($verbose) {
      if (!defined($simpid = fork())) {
	# fork returned undef, so failed
	die "cannot fork: $!";
      } elsif ($simpid == 0) {
	# fork returned 0, so this branch is the child
	exec("$commandline");
	# if the exec fails, fall through to the next statement
	die "can't exec $commandline : $!";
      } else { 
	# fork returned neither 0 nor undef, 
	# so this branch is the parent
	waitpid($simpid, 0);
      } 
      #system("$commandline");
    } else { # not verbose
      print STDERR "\n" if $verbose;
      #      print STDERR grep /$output_filter_pattern/,`$commandline > simlog 2>&1`;
      #or, with a pipe:
      $simpid = open(SIM, "$commandline 2>&1 |") || die "can't fork: $!"; 
      open(LOG,">simlog");
      while (<SIM>) {
	print LOG;
	/$output_filter_pattern/ && do {
	  print STDERR;# if $verbose;
	};
      } # while simulation is running
      close LOG;
      my $ppid=getpgrp($simpid);
      if(not $ppid) {
	close SIM || die "Trouble with $commandline: $! $?";
      }
      print STDERR "\n" if $verbose;
    } #verbose or not
# } # if simulations not disabled

  if($nsims>1) {
    #Postprocessing
    &egrep($output_filter_pattern,"${simtype}_C${count}_${simn}.out",'>>',"${simtype}_C${count}_.out");
  }
  } # if simulations not disabled
  my $i=($nsims>1)?$simn-1:0;
  open(RES,"<${simtype}_C${count}_${simn}.out");
  $results[$i]=<RES>;
  my $another=<RES>; # This takes the next line, if any,
  if($another) { # and if there is one, it assigns the filename to $results[$i]
    $results[$i]="${simtype}_C${count}_${simn}.out";
  }
  close RES;
} # nsims 

#Postprocessing after sweep
#if($nosims==0) {
&egrep($output_filter_pattern, "${simtype}_C${count}_.out", '>>', "${simtype}_C$count.res");
#NEW01072003#&egrep($output_filter_pattern, "${simtype}_C${count}_.out", '>>', $resfile);
#}
chdir "$workingdir";

return \@results; # PostProcessors are only called after &main() exits.
} #END of main()

#========================================================================================
#  NEW IMPLEMENTATION TO ALLOW POSTPROCESSING AFTER EVERY ELEMENT IN SWEEP
#========================================================================================
my @results=();
my %simdata=();
my $simtype='NO_SIMTYPE';
my $dataset='NO_DATASET';
my $count=0;
my ($batch,$interactive,$nosims,$plot,$verbose,$warn);
my $output_filter_pattern= '.*';
my $command='perl inputfile outputfile'; 
my $dirname= 'NO_DIRNAME';
my $devtype='NO_DEVTYPE';
my $simtitle='NO_TITLE';
my $title="#$devtype $simtype simulation\n";
my $ext='.templ';
my $extin='.pl';
my $workingdir = 'NO_WORKINGDIR';
#------------------------------------------------------------------------------
#&main(\$dataset,\$i,\$dataref,\$flagsref);
#&pre_run(\$dataset,\$i,\$dataref,\$flagsref);
#&run(\$dataset,\$i,\$dataref,\$flagsref);
#&post_run(\$dataset,\$i,\$dataref,\$flagsref);

sub pre_run {

use Cwd;

$dataset=shift; 
$count=shift;
my $dataref=shift;
my $flagsref=shift;
($batch,$interactive,$nosims,$plot,$verbose,$warn)=@{$flagsref};

(my $nsims, my $simdataref)=@{$dataref};

print STDERR '#',"-" x 79, "\n" if $verbose;## Simulation run $count\n";

%simdata=%{$simdataref};
#my @results=();
$command=$simdata{COMMAND}||'perl inputfile outputfile'; 

$output_filter_pattern=$simdata{OUTPUT_FILTER_PATTERN}|| '.*';
$simtype=$simdata{SIMTYPE}||'';
 $dirname= "${simtype}-$dataset";
 $devtype=$simdata{DEVTYPE}||'';
 $simtitle=$simdata{TITLE};
foreach my $key (keys %simdata) {
($key!~/^_/) && next;
($simtitle=~/$key/) && do {
$simtitle=~s/$key/$key:$simdata{$key}/;
};
}
 $title="#$simtitle\n"||"#$devtype $simtype simulation\n";
 $ext=$simdata{TEMPL}||'.templ';
 $extin=$simdata{EXT}||'.pl';
 $workingdir =cwd();
chdir  "$workingdir/$dirname";
return $nsims;
} #END of pre_run()
#------------------------------------------------------------------------------
sub run {

my $nsims=shift;
my $simn=shift;

#use Cwd;
#my ($nsims, my $simdataref)=@{$dataref};

## INPUT FILE CREATION

#foreach my $simn (1..$nsims) {
  if($nsims==1){$simn=''} else {
    print STDERR "# Subrun $simn of $nsims \n" if $verbose;
  }
  my $inputfile= "${simtype}_${simn}$extin";
  my $outputfile= "${simtype}_C${count}_${simn}.out";
  my $commandline=$command;
  $commandline=~s/inputfile/$inputfile/ig;
  $commandline=~s/outputfile/$outputfile/ig;
  
  open (NEW, ">$inputfile");
  print NEW ("$title");

  foreach my $type ($devtype,$simtype) {
    if($type) {
      my $nsim=($simn eq '')?0:$simn;
      &gen_sim_script ($nsim-1,"$simtype$ext",\%simdata,\*NEW,$dataset,$warn);
      print NEW ("\n");
    }
  } # device and simulation templates
  close (NEW);
  
  if($nosims==0) {
    if($verbose) {
      if (!defined($simpid = fork())) {
	# fork returned undef, so failed
	die "cannot fork: $!";
      } elsif ($simpid == 0) {
	# fork returned 0, so this branch is the child
	exec("$commandline");
	# if the exec fails, fall through to the next statement
	die "can't exec $commandline : $!";
      } else { 
	# fork returned neither 0 nor undef, 
	# so this branch is the parent
	waitpid($simpid, 0);
      } 
      # system("$commandline");
    } else { # not verbose
      print STDERR "\n" if $verbose;
      #      print STDERR grep /$output_filter_pattern/,`$commandline > simlog 2>&1`;
      #or, with a pipe:
      $simpid = open(SIM, "$commandline 2>&1 |") || die "can't fork: $!"; 
      open(LOG,">simlog");
      while (<SIM>) {
	print LOG;
	/$output_filter_pattern/ && do {
	  print STDERR;# if $verbose;
	};
      } # while sinulation is running
      close LOG;
      my $ppid=getpgrp($simpid);
      if(not $ppid) {
	close SIM || die "Trouble with $commandline: $! $?";
      }
      print STDERR "\n" if $verbose;
    } #verbose or not
#  } # if simulations not disabled
  if($nsims>1) {
    #Postprocessing
    &egrep($output_filter_pattern,"${simtype}_C${count}_${simn}.out",'>>',"${simtype}_C${count}_.out");
  }
  } # if simulations not disabled
  my $i=($nsims>1)?$simn-1:0;
  open(RES,"<${simtype}_C${count}_${simn}.out");
  $results[$i]=<RES>;
  my $another=<RES>; # This takes the next line, if any,
  if($another) { # and if there is one, it assigns the filename to $results[$i]
    $results[$i]="${simtype}_C${count}_${simn}.out";
  }
  close RES;
#} # nsims 
#no need to return @results, it's a package global now. Maybe return $results[$i], makes more sense.
#return \@results; # PostProcessors are only called after &main() exits.
return $results[$i]; # PostProcessors are only called after &main() exits.
} # END of run()
#------------------------------------------------------------------------------
sub post_run {
  if($nosims==0){
#Postprocessing after sweep
&egrep($output_filter_pattern, "${simtype}_C${count}_.out", '>>', "${simtype}_C$count.res");
}
chdir "$workingdir";

return \@results; # PostProcessors are only called after &main() exits.

} # END of post_run()
#==============================================================================

#print STDERR "\n","#" x 80,"\n#\t\t\tSynSim simulation automation tool\n#\n#  (c) Wim Vanderbauwhede 2000,2002-2003. All rights reserved.\n#  This program is free software; you can redistribute it and/or modify it\n#  under the same terms as Perl itself.\n#\n","#" x 80,"\n";

#-------------------------------------------
# SUBROUTINES used by main, pre_run, run, post_run
#-------------------------------------------

#--------------------------------------
# GENERATION OF THE SIMULATION SCRIPT
#--------------------------------------

#WV What happens: the templates for _SIMTYPE  are read in
#WV and the variables are substituted with the values from the .data file

sub gen_sim_script {

my $nsim=shift;
my $templfilename=shift;
my $simdataref=shift;
my %simdata=%{$simdataref};
my $fh=shift; 
my $dataset=shift;
my $warn=shift;
my %exprdata=();
my %keywords=();
foreach my $key ( sort keys %simdata) {
#  ($key!~/^_/) && next;
#make sure substitutions happen in keyword values too
  if ($key!~/^_/ ) {
    if( $simdata{$key}=~/^_/) {
my $parameter=$simdata{$key};
${$keywords{$parameter}}{$key}=1;
}
next;
}

  if(@{$simdata{$key}}==1) {
    $exprdata{$key}=&check_for_expressions(\%simdata,$key,$nsim);
    foreach my $keyword (keys %{$keywords{$key}}) {

$simdata{$keyword}=$exprdata{$key};

}
  } # if..else
} # foreach 

	# OPEN TEMPLATE
	open (TEMPL, "<$templfilename")||die "Can't open $templfilename\n";

	while (my $line = <TEMPL>) {

		  foreach my $key (keys %simdata) {
		    ($key!~/^_/) && next;
			my $ndata=@{$simdata{$key}};
			if($ndata>1) {
			  if($line =~ s/$key(?!\w)/$simdata{$key}->[$nsim]/g){
#			  print STDERR "# $key = ",$simdata{$key}->[$nsim],"\n" if $warn;
			}
			} else {
#			  my $simdata=&check_for_expressions(\%simdata,$key,$nsim);
			  #A dangerous addidtion to make SynSim handle words
			  $exprdata{$key}||=$simdata{$key}->[0];
			  $line =~ s/$key(?!\w)/$exprdata{$key}/g;
			  #print STDERR "# $key = ",$simdata{$key}->[0],"\nLINE:$line\n" if $warn;
			} # if..else

		      } # foreach 

		  # check for undefined variables
		  while($line=~/\b(_\w+?)\b/&&$line!~/$1\$/) {
		    my $nondefvar=$1;
		    $line=~s/$nondefvar/0/g; # All undefined vars substituted by 0
		    print STDERR "\nWarning: $nondefvar ($templfilename) not defined in $dataset.\n" if $warn; 
		  } # if some parameter is still there
		  print $fh $line;
		} # while
close TEMPL;

} # END OF gen_sim_script 
#------------------------------------------------------------------------------
sub egrep {
my $pattern=shift;
my $infile=shift;
my $mode=shift;
my $outfile=shift;
open(IN,"<$infile");
open(OUT,"$mode$outfile");
print OUT grep /$pattern/,<IN>;

close IN;
close OUT;
}
#------------------------------------------------------------------------------
sub check_for_expressions {
my $dataref=shift;
my $key=shift;
my $nsim=shift;
my %simdata=%{$dataref};	
my $expr=$simdata{$key}->[0];
if($expr=~/(_[A-Z_]+)/) { # was "if"
while($expr=~/(_[A-Z_]+)/) { # was "if"
#variable contains other variables
#_A =3*log(_B)+_C*10-_D**2
#_A =3 ;log;_B;;_C;10;_D;;2
my @maybevars=split(/[\ \*\+\-\/\^\(\)\[\]\{\}\?\:\=\>\<]+/,$expr);
my @vars=();
foreach my $maybevar ( @maybevars){
($maybevar=~/_[A-Z]+/)&& push @vars,$maybevar;
}
foreach my $var (@vars) {
my $simn=(@{$simdata{$var}}==1)?0:$nsim;
$expr=~s/$var/$simdata{$var}->[$simn]/g;
}
}
#print STDERR "$key=$expr=>",eval($expr),"\n";
}
return eval($expr);
}

################################################################################
#
# These routines are not used by synsim
# They are used by make install
#
################################################################################

# Create simulation directory etc.
sub setup {
  use File::Copy;
my $HOME=$ENV{HOME};
print "Local SinSym directory? [$HOME/SynSim]:";
my $synsimroot=<STDIN>;
chomp $synsimroot;
if(not $synsimroot){$synsimroot="$HOME/SynSim"}
  if(not -d "$synsimroot"){
mkdir "$synsimroot", 0755;
  }
print "Simulation project name? [SynSimProject]:";
my $project=<STDIN>;
chomp $project;
if(not $project){$project='SynSimProject'}


print "Creating $project directory structure in $synsimroot...\n";
mkdir "$synsimroot/$project", 0755;
mkdir "$synsimroot/$project/SOURCES", 0755;
mkdir "$synsimroot/$project/TEMPLATES", 0755;
mkdir "$synsimroot/$project/TEMPLATES/DEVTYPES", 0755;
mkdir "$synsimroot/$project/TEMPLATES/SIMTYPES", 0755;
  if(-d "eg"){
    if(-e "eg/synsim"){
copy("eg/synsim","$synsimroot/$project/synsim");
}
    if(-e "eg/synsim.data"){
copy("eg/synsim.data","$synsimroot/$project/synsim.data");
}
  }

&localinstall(0,$synsimroot);

} # END of setup()

#------------------------------------------------------------------------------

# Local Simulation::Automate (SynSim) installation
sub localinstall {
my $full=shift||1;
my $synsimroot=shift||'';
  use File::Copy;
my $HOME=$ENV{HOME};
if(not $synsimroot) {
print "Local SinSym directory? [$HOME/SynSim]:";
$synsimroot=<STDIN>;
chomp $synsimroot;
if(not $synsimroot) {$synsimroot="$HOME/SynSim"}
}
  if(not -d "$synsimroot"){
mkdir "$synsimroot", 0755;
  }
print "Creating local SynSim directory $synsimroot/Simulation/Automate ...\n";
  if(not -d  "$synsimroot/Simulation") {
mkdir "$synsimroot/Simulation", 0755;
}
  if(not -d  "$synsimroot/Simulation") {
mkdir "$synsimroot/Simulation", 0755;
}
  if(not -d  "$synsimroot/Simulation/Automate") {
mkdir "$synsimroot/Simulation/Automate", 0755;
}
  if(-d "Automate") {  
foreach my $module (qw(PostProcessors Dictionary)) {
if( -e "Automate/$module.pm"){
copy("Automate/$module.pm", "$synsimroot/Simulation/Automate/$module.pm");
}
}
if($full) {
  foreach my $module (qw(Remote PostProcLib Analysis)){
if( -e "Automate/$module.pm"){
copy("Automate/$module.pm", "$synsimroot/Simulation/Automate/$module.pm");
}
}
if( -e "Automate.pm"){
copy("Automate.pm", "$synsimroot/Simulation/Automate.pm");
}
} # if full local install
} # if directory Automate exists in current dir. 

} # END of localinstall()

######################## User Documentation ##########################


## To format the following documentation into a more readable format,
## use one of these programs: perldoc; pod2man; pod2html; pod2text.
## For example, to nicely format this documentation for printing, you
## may use pod2man and groff to convert to postscript:
##   pod2man Automate.pod | groff -man -Tps > Automate.ps


=head1 NAME

Simulation::Automate - A Simulation Automation Tool

The set of modules is called B<Simulation::Automate>.

The tool itself is called B<SynSim>, the command C<synsim>.

=head1 REQUIREMENTS

=over

=item *

a unix-like system

=item *

perl 5

=item *

gnuplot for postprocessing (optional)

=back

=head1 SYNOPSIS

       use Simulation::Automate;

       &synsim();

=head1 DESCRIPTION

SynSim is a generic template-driven simulation automation tool. It works with any simulator that accepts text input files and generates text output (and even those that don't. See L<EXAMPLES> for special cases). It executes thousands of simulations with different input files automatically, and processes the results. Postprocessing facilities include basic statistical analysis and automatic generation of PostScript plots with Gnuplot. SynSim is entirely modular, making it easy to add your own analysis and postprocessing routines.

=head1 INSTALLATION

=over

=item 1.
Download the gzipped tar file F<Simulation-Automate-0.9.5.tar.gz>

=item 2.
Extract the archive:

	tar -xvf Simulation-Automate-0.9.5.tar.gz

=item 3.
Create the Makefile:

	cd Simulation-Automate-0.9.5
	perl Makefile.PL

=item 4.
Make Simulation::Automate:

	make

=item 5.
Test Simulation::Automate:

	 make test

=item 6.
Install Simulation::Automate:

	 make install

=item 7.
For a local installation (if you don't have root access):

	 make localinstall

or

	 perl -e "use Simulation::Automate;&Simulation::Automate::localinstall();"

=item 8.
Setup your local SynSim project (SynSim is the name for the tool contained in Simulation::Automate). This creates the directory structure for your simulations:

	 make setup
or

	 perl -e "use Simulation::Automate;&Simulation::Automate::setup();"


=back

The archive structure is as follows:

	README    
	Makefile.PL	  
        Automate.pm
	Automate/
                Remote.pm
        	PostProcLib.pm
                Analysis.pm
		Dictionary.pm
             	PostProcessors.pm

	eg/
		synsim	
		synsim.data
		ErrorFlags.data
		Histogram.data
		SweepVar.data
		Expressions.data
		gnuplot.data
		SOURCES/
			bufsim3.cc
			MersenneTwister.h
		TEMPLATES/		
			DEVTYPES/
			SIMTYPES/
				bufsim3.templ


=head1 CONFIGURATION

SynSim must be configured for use with your simulator. This is done by providing template and source files, creating (or modifying) datafiles and (optionally) customizing some modules for postprocessing the simulation results. All files must be put in a particilar directory structure:

=head2 Directory structure

You can use "make setup"  to create a SynSim directory structure. If you want to create it manually, this is the structure:

	YourProject/
			synsim	
			YourDataFile.data
			[SOURCES/]
			TEMPLATES/		
				 [DEVTYPES/]
				 SIMTYPES/
					YourSimTempl.templ

	[Simulation/SynSim/]
				[Dictionary.pm]
				[PostProcessors.pm]			

The synsim script contains the 2 lines from the L<SYNOPSIS>. 
The local Simulation/Automate modules are only required if you want to customize the postprocessing (highly recommended). 
 
=head2 Source files

Copy all files which are needed "read-only" by your simulator (e.g. header files, library files) to F<SOURCES/>. This directory is optional.

=head2 Template files

Template files are files in which simulation variables will be substituted by their values to create the input file for your simulator. SynSim can create an input file by combining two different template files, generally called device templates and simulation templates. This is useful in case you want to run different types of simulations on different devices, e.g. DC analysis, transient simulations, small-signal and noise analysis  on 4 different types of operation amplifiers. In total, this requires 16 different input files, but only 8 different template files (4 for the simulation type, 4 for the device types).

=over

=item 1.

To create a template file, start from an existing input file for your simulator. Replace the values of the variables to be modified by SynSim by a SynSim variable name (e.g. 
var1 = 2.5 => var1 = _VAR1). 

=item 2.

Put the template files in F<TEMPLATES/SIMTYPES> and F<TEMPLATES/DEVTYPES>.


There must be at least one template file in F<SIMTYPES>; files in F<DEVTYPES> are optional.
SynSim will check both directories for files as defined in the datafile. If a matching file is found in F<DEVTYPES>, it will be prepended to the simulation template from F<SIMTYPES>. This is useful if the datafile defines multiple simulation types on a particular device (See L<DATAFILE DESCRIPTION> for more information).

=back

B<NOTE:>

SynSim creates a run directory ath the same level as the SOURCES and TEMPLATES directories. All commands (compilations etc.) are executed in that directory. As a consequence, paths to source files (e.g. header files) should be "C<../SOURCES/>I<sourcefilename>".


=head2 Datafile

The datafile is the input file for synsim. It contains the list of simulation variables and their values to be substituted in the template files, as well as a number of configuration variables (See L<DATAFILE DESCRIPTION> for more information).

=head2 Postprocessing (optional)

The F<PostProcessing.pm> module contains routines to perform postprocessing on the simulation results. A number of generic routines are provided, as well as a library of functions to make it easier to develop your own postprocessing routines. See L<POSTPROCESSING> for a full description).

=head2 Dictionary (optional)

The F<Dictionary.pm> module contains descriptions of the parameters used in the simulation. These descriptions are used by the postprocessing routines to make the simulation results more readable. See L<DICTIONARY> for a full description).

=head1 DATAFILE DESCRIPTION

The datafile defines which simulations to run, with which parameter values to use, and how to run the simulation. By convention, it has the extension C<.data>.

=head2 Syntax

The datafile is a case-sensitive text file with following syntax:

=over

=item Comments and blanks

Comments are preceded by '#'. 
Comments, blanks and empty lines are ignored

=item Simulation variables 

Simulation variables ("parameters") are in UPPERCASE with a leading '_', and must be separated from their values with a '='.

=item Configuration variables 

Configuration variables ("keywords") are in UPPERCASE, and must be separated from their values with a ':'.

=item Lists of values

Lists of values have one or more items. Valid list separators are ',',';' and, for a 2-element list, '..'.

If a (','- or ';'-separated) list has 3 elements START,STOP,STEP |START|<|STOP| and |STEP|<|STOP-START|, then this list will be expanded as a for-loop from START to STOP with step STEP.

=item Section headers for multiple simulation types

These must be lines containing only the simulation type 

=back

=head2 Simulation variables 

The main purpose of the datafile is to provide a list of all variables and their values to be substituted in the template files. 
The lists of values for the variables can be used in two different ways: 

=over

=item Comma-separated list: combine values

A simulation will be performed for every possible combination of the values for all parameters. 

Example:

	_PAR1 = 1,2
	_PAR2 = 3,4,5

defines 6 simulations: (_PAR1,_PAR2)=(1,3),(1,4),(1,5),(2,3),(2,4),(2,5)

Simulation results for all values in ','-separated list are stored in a separate files.


=item Semicolon-separated list: pair values

If more than one ';'-separated list exists, they must have the same number of items. The values of all parameters at the same position in the list will be used.

Example:

	_PAR1 = 0;1;2;4
	_PAR2 = 3;4;5;6

defines 3 simulations: (_PAR1,_PAR2)=(0,3);(1,4);(2,5);(4,6)

Values from ';'-separated lists are processed one after another while are values for all others parameters are kept constant. In other words, the ';'-separated list is the innermost of all nested loops.

Simulation results for all values in the ';'-separated list are stored in a common file. For this reason, ';'-separated lists are preferred as sweep variables (X-axis values), whereas ','-separated lists are more suited for parameters (sets of curves).

Example: consider simulation of packet loss vs number of buffers with 3 types of buffer and 2 different traffic distributions.

	_NBUFS = 4;8;16;32;64;128
	_BUFTYPE = 1,2,3
	_TRAFDIST = 1,2

This will produces 6 files, each file containing the simulation results for all values of _NBUFS. A plot of this simulation would show a set of 6 curves, with _NBUFS as X-axis variable.

=item Semicolon-separated from;to;step list

This is a special case where the list has exactly three elements From;To;Step and following condition holds:

  (|From|<|To|) AND (|Step|<|To-From|)

Example:

       _NBUFS = 16;64;8 #  from 16 to 64 in steps if 8: 16;24;32;40;48;56;64

=item Double dotted list

This is a shorthand for a ';'-separated list if the value increase in steps of 1. E.g. 0..7 is equivalent to 0;1;2;3;4;5;6;7.

=back

=head2 Configuration variables

A number of variables are provided to configure SynSim's behaviour:

=over

=item INCLUDE (optional)

If the value of INCLUDE is an exisiting filename, this datafile will be included on the spot.

=item COMMAND

The program that runs the input file, i.e. the simulator command (default: perl).

=item EXT

Extension of input file (default: .pl)

=item TEMPL

Extension of template files (default: .templ)

=item SIMTYPE

The type of simulation to perform. This can be a ','-separated list. SynSim will look in TEMPLATES/SIMTYPES for a file with TEMPL and SIMTYPE

=item DEVTYPE (optional)

The name of the device on which to perform the simulation. If defined, SynSim will look in TEMPLATES/DEVTYPES for a file with TEMPL and DEVTYPE, and prepend this file to the simulation template before parsing.

=item OUTPUT_FILTER_PATTERN

A Perl regular expression to filter the output of the simulation (default : .*).

=item ANALYSIS_TEMPLATE

Name of the routine to be used for the result analysis (postprocessing). This routine must be defined in PostProcessors.pm (default: SweepVar, a generic routine which assumes a sweep for one variable and uses all others as parameters).

=item SWEEPVAR (optional)

The name of the variable to be sweeped. Mandatory if the postprocessing routine is SweepVar. 

=item NORMVAR (optional)

The name of the variable to normalise the results with. The results will be divided by the corresponding value of the variable.

=item NRUNS (optional)

The number of times the simulation has to be performed. For statistical work.

=item DATACOL (optional)

The column in the output file which contains simulation results (default: 2). Mandatory if using any of the generic postprocessing routines. 

=item TITLE (optional)

String describing the simulation, for use in the postprocessing.

=item XLABEL, YLABEL, LOGSCALE, STYLE

Variables to allow more flexibility in the customization of the plots. XLABEL and YLABEL are the X and Y axis labels. LOGSCALE is either X, Y or XY, and results in a logarithmic scale for the chosen axis. STYLE is the gnuplot plot style (lines, points etc)

=item XTICS, YTICS, XSTART, XSTOP, YSTART, YSTOP

Variables to allow more flexibility in the customization of the plots (not implemented yet).

=back

=head2 Expressions

The SynSim datafile has support for expressions, i.e. it is possible to express the value list of a variable in terms of the values of other variables.

Example:

    # average packet length for IP dist 
    _MEANPL = ((_AGGREGATE==0)?2784:9120)
    # average gap width 
    _MEANGW= int(_MEANPL*(1/_LOAD-1)) 
    # average load
    _LOAD = 0.1;0.2;0.3;0.4;0.5;0.6;0.7;0.8;0.9
    # aggregate 
    _AGGREGATE =  0,12000

The variables used in the expressions must be defined in the datafile, although not upfront. Using circular references will not work.
The expression syntax is Perl syntax, so any Perl function can be used. Due to the binding rules, it is necessary to enclose expressions using the ternary operator ?: with brackets (see example).

The next sections (L<DICTIONARY> and L<POSTPROCESSING>) are optional. For instructions on how to run SynSim, go to L<RUNNING SYNSIM>.



=head1 DICTIONARY

The F<Dictionary.pm> module contains descriptions of the parameters used in the simulation. These descriptions are used by the postprocessing routines to make the simulation results more readable. The dictionary is stored in an associative array called C<make_nice>. The description of the variable is stored in a field called 'title'; Descriptions of values are stored in fields indexed by the values.

Following example illustrates the syntax:

	# Translate the parameter names and values into something meaningful
	%Dictionary::make_nice=(
	
	_BUFTYPE => {
	title=>'Buffer type',
		     0=>'Adjustable',
		     1=>'Fixed-length',
		     2=>'Multi-exit',
		    },
	_YOURVAR1 => {
	title=>'Your description for variable 1',
	},
	
	_YOURVAR2 => {
	title=>'Your description for variable 2',
'val1' => 'First value of _YOURVAR2',
'val3' => 'Second value of _YOURVAR2',
	},

	);

=head1 POSTPROCESSING

Postprocessing of the simulation results is handled by routines in the C<PostProcessors.pm> module. This module uses the C<PostProcLib.pm> and C<Analysis.pm>.

=head2 PostProcessors

Routines to perform analysis on the simulation results in the PostProcessors module. In general you will have to create your own routines, but the version of C<PostProcessors.pm> in the distribution contains a number of more or less generic postprocessing routines. All of these have hooks for simple functions that modify a file in-place. To call these functions, include them in the datafile with the C<PREPROCESSOR> variable. e.g:

  PREPROCESSOR : modify_results_file

All functions must be put in PostProcessors.pm, and the template could be like this:

  sub modify_results_file {
  my $resultsfile=shift;
  
  open(IN,"<$resultsfile");
  open(TMP,">$resultsfile.tmp");
  while(<IN>) {
  #Do whatever is required
  }
  close IN;
  close TMP;
  rename "$resultsfile.tmp","$resultsfile" or die $!;
  }

=over

=item SweepVar

Required configuration variables: C<SWEEPVAR>

Creates a plot using C<SWEEPVAR> as X-axis and all other variables as parameters. This routine is completely generic. The C<SWEEPVAR> value list must be semicolon-separated.

=item SweepVarCond

Required configuration variables: C<SETVAR>,C<SWEEPVAR> and C<CONDITION>. 

Creates a plot using C<SETVAR> as X-axis; C<SWEEPVAR> is checked against the condition C<COND> (or C<CONDITION>). The first value of C<SWEEPVAR> that meets the condition is plotted. All other variables are parameters. This routine is completely generic. The C<SWEEPVAR> value list must be semicolon-separated.

=item ErrorFlags

Required configuration variables: C<SWEEPVAR>, C<NRUNS>

Optional configuration variables: C<NSIGMAS>

Creates a plot using C<SWEEPVAR> as X-axis and all other variables as paramters. Calculates average and 95% confidence intervals for C<NRUNS> simulation runs and plots error flags. This routine is fully generic, the confidence interval (95% by default) can be set with NSIGMAS. See eg/ErrorFlags.data for an example datafile. The C<SWEEPVAR> value list must be semicolon-separated.

=item Histogram

Required configuration variables: C<NBINS>

Optional configuration variables: C<BINWIDTH>, C<OUTPUT_FILTER_PATTERN>, C<NSIGMAS>

Creates a histogram of the simulation results. This requires the simulator to produce raw data for the histograms in a tabular format. The configuration variable C<OUTPUT_FILTER_PATTERN> can be used to 'grep' the simulator output. When specifying logscale X or XY for the plot, the histogram bins will be logarithmic. See eg/Histogram.data for an example. 
The number of bins in the histogram must be specified via C<NBINS>. The width of the bins can be set with C<BINWIDTH>.

=back

=head2 PostProcLib

In a lot of cases you will want to create your own postprocessing routines. To make this easier, a library of functions is at your disposal. This library resides in the C<PostProcLib.pm> module. 

Following functions are exported:

			   &prepare_plot	# does what it says. see example below
			   &gnuplot		# idem. Just pipes the first argument string to gnuplot. The option -persist can be added to keep the plot window after gnuplot exits.
			   &gnuplot_combined	# See example, most useful to create nice plots. Looks for all files matching ${simtempl}-${anatempl}-*.res, and creates a line in the gnuplot script based on a template you provide.	

Following variables are exported (see PostProcLib.pm for a full list):

			   %simdata		# contains all simulation variables and their value lists
			   @results		# an array of all results for a sweep (i.e. a var with a ';'-sep. value list
			   $sweepvar		# SWEEPVAR
			   $normvar		# NORMVAR
			   $sweepvals		# string containing all names and values of parameters for the sweep, joined with '-'
			   $datacol		# DATACOL
			   $count		# cfr. OUTPUT FILES section
			   $simtempl		# SIMTYPE
			   $anatempl		# ANALYSIS_TEMPLATE
			   $dirname		# name of run directory. cfr. OUTPUT FILES section
			   $last		# indicates end of a sweep
			   $verylast		# indicates end of all simulations
			   $sweepvartitle	# title for SWEEPVAR (from Dictionary.pm) 
			   $title		# TITLE 
			   $legend		# plot legend (uses Dictionary.pm)
			   $legendtitle		# plot legend title (uses Dictionary.pm)
                           $xlabel		# XLABEL	
                           $ylabel		# YLABEL	
                           $logscale		# LOGSCALE
			   $plot		# corresponds to -p flag
			   $interactive		# corresponds to -i flag

An example of how all this is used:

	sub YourRoutine {
	## Unless you want to dig really deep into the code, start all your routines like this:
	## Get all arguments, to whit: $datafilename,$count,$dataref,$flagsref,$returnvalue
	my @args=@_; 
	## But don't bother with these, following function does all the processing for you:
	&prepare_plot(@args);
	
	## this makes all above-listed variables available
	
	## Define your own variables.
	## As every variable can have a list of values, 
	## $simdata{'_YOURVAR1'} is an array reference.
	
	my $yourvar=${$simdata{'_YOURVAR1'}}[0];
	
	my @sweepvarvals=@{$simdata{$sweepvar}};
	
	## $verylast indicates the end of all simulations
	if($verylast==0) {
	
	## what to do for all simulations
	
	## example: parse SynSim .res file and put into final files for gnuplot
	
	open(HEAD,">${simtempl}-${anatempl}-${sweepvals}.res");
	open(IN,"<${simtempl}_C$count.res");
	while(<IN>) {
		/\#/ && !/Parameters|$sweepvar/ && do {
		## do something with $_
		print HEAD $_
		};
	}
	close IN;
	close HEAD;

	my $i=0;
	foreach my $sweepvarval ( @sweepvarvals ) {
		open(RES,">>${simtempl}-${anatempl}-${sweepvals}.res");
		print RES "$sweepvarval\t$results[$i]";
		close RES;
		$i++;
	}

	## $last indicates the end of a sweep
	if($last) {
	  ## $interactive corresponds to the -i flag
		  if($interactive) {
		    ## do something, typically plot intermediate results
		my $gnuplotscript=<<"ENDS";
		# your gnuplot script here
		ENDS
	
		&gnuplot($gnuplotscript);
	
		}		# if interactive
	  }			# if last
	} else {
	 ## On the very last run, collect the results into one nice plot
	
	## You must provide a template line for gnuplot. Next line is a good working example.
	## This line will be eval()'ed by the &gnuplot_combined() routine. 
	## This means the variables $filename and $legend are defined in the scope of this routine. 
	## Don't locally scoped put variables in there, use the substitution trick as below or some other way.
	
	#this is very critical. The quotes really matter!
	# as a rule, quotes inside gnuplot commands must be escaped
	
	my $plotlinetempl=q["\'$filename\' using (\$1*1):(\$_DATACOL) title \"$legend\" with lines"];
	$plotlinetempl=~s/_DATACOL/$datacol/; ##this is a trick, you might try to eval() the previous line or something. TIMTOWDI :-)
	
	my $firstplotline=<<"ENDH";
	# header for your gnuplot script here
	ENDH
	
	&gnuplot_combined($firstplotline,$plotlinetempl);
	}
	
	} #END of YourRoutine()


=head2 Statistical analysis

A module for basic statistical analysis is also available (C<Analysis.pm>). Currently, the module provides 2 routines: 

=over

=item calc_statistics()

To calculate average, standard deviation, min. and max. of a set of values.

Arguments:

	$file: name of the results file. The routine requires the data to be in whitespace-separated columns.  	
	$par: Determines if the data will be differentiated before processing ($par='DIFF') or not (any other value for $par). Differentiation is defined as subtracting the previous value in the array form the current value. A '0' is prepended to the array to avoid an undefined first point.
	$datacol: column to use for data
	$title: optional, a title for the histogram 
	$log: optional, log of values before calculating histogram or not ('LOG' or '')

Use:
	my $file="your_results_file.res";
	my $par='YOURPAR';
	my $datacol=2;
	my %stats=%{&calc_statistics($file,[$par, $datacol])};

	my $avg=$stats{$par}{AVG}; # average
	my $stdev=$stats{$par}{STDEV}; # standard deviation
	my $min=$stats{$par}{MIN}; # min. value in set
	my $max=$stats{$par}{MAX}; # max. value in set

=item build_histograms()

To build histograms. There are 3 extra arguments:

	$nbins: number of bins in the histogram
	$min: force the value of the smallest bin (optional)
	$max: force the value of the largest bin (optional)

use:
	my $par='DATA';
	my %hists=%{&build_histograms("your_results_file.res",[$par,$datacol],$title,$log,$nbins,$min,$max)};

NOTE: Because the extra arguments are last, the $title and $log arguments can not be omitted. If not needed, supply ''.

=back


=head1 RUNNING SYNSIM

The SynSim script must be executed in a subdirectory of the SynSim
directory which contains the TEMPLATES subdir and the datafile (like the Example directory in the distribution). 

The command line is as follows:

	./synsim [-h -i -p -w -v -N -P -f] [datafile] [remote hostname]

The C<synsim> script supports following command line options:

	none: defaults to -f synsim.data
	 -f [filename]: 'file input'. Expects a file containing info about simulation and device type. 
	 -p : plot. This enables generation of postscript plots via gnuplot. A postprocessing routine is required to generate the plots.
	 -i : interactive. Enables generation of a plot on the screen after every iteration. Assumes -p -v.  A postprocessing routine is required to generate the plots.
	 -v : 'verbose'. Sends simulator output to STDOUT, otherwise to the [rundir]/simlog file
	 -w : 'warn'. Show warnings about undefined variables
	 -N : 'No simulations'. Perform only postprocessing.
	 -P : 'Plot only'. Only plots the generated PostScript file. 
	 -h, -? : short help message

If [remote hostname] is provided, SynSim will try to run the simulation on the remote host.

The current implementation requires:

-ssh access to remote host

-scp access to remote host

-rsync server on the local host

-or,alternatively, an NFS mounted home directory

-as such, it will (probably) only work on Linux and similar systems

=head1 OUTPUT FILES

SynSim creates a run directory C<{SIMTYPE}->I<[datafile without .data]>. It copies all necessary template files and source files to this directory; all output files are generated in this directory.

SynSim generates following files:

=over

=item *

Output files for all simulation runs. 

The names of these files are are C<{SIMTYPE}_C>I<[counter]_[simulation number]>C<.out>

I<counter> is increased with every new combination of variables in ','-separated lists 

I<simulation number> is the position of the value in the ';'-separated list. 

=item *

Combined output file for all values in a ';'-separated list. 

The names of these files are are C<{SIMTYPE}_C>I<[counter]>C<_.out> 

I<counter> is increased with every new combination of variables in ','-separated lists. 

Only the lines matching C</OUTPUT_FILTER_PATTERN/> (treated as a Perl regular expression) are put in this file.

=item *

Combined output file for all values in a ';'-separated list, with a header detailing all values for all variables. 

The names of these files are are C<{SIMTYPE}_C>I<[counter]>C<.res>, 

I<counter> is increased with every new combination of variables in ','-separated lists.  

Only the lines in the C<.out> files matching C</OUTPUT_FILTER_PATTERN/> (treated as a Perl regular expression) are put in this file.


=item *

Separate input files for every item in a ';'-separated list. 

The names of these files are are C<{SIMTYPE}_>I<[simulation number]>C<.{EXT}>

I<simulation number> is the position of the value in the list. 

These files are overwritten for every combination of variables in ','-separated lists.

=back

=head1 EXAMPLES

Here are some examples of how to use SynSim for different types of simulators.

=head2 1. Typical SPICE simulator

Normal use: spice -b circuit.sp > circuit.out

With SynSim:

=over

=item 1. Create a template file

Copy circuit.sp to TEMPLATES/SIMTYPE/circuit.templ
Replace all variable values with SynSim variable names.

e.g. a MOS device line in SPICE:

  M1 VD VG VS VB nch w=10u l=10u

becomes

  M1 VD VG VS VB _MODEL w=_WIDTH l=_LENGTH

=item 2. Create a data file (e.g. circuit.data)

  TITLE: MOS drain current vs. length
  SIMTYPE : circuit
  COMMAND : spice -b inputfile > outputfile

  # Required for postprocessing 
  OUTPUT_FILTER_PATTERN : id # keep only the drain current on the output file
  ANALYSIS_TEMPLATE : SweepVar # default template for simple sweep
  SWEEPVAR : _L # we sweep the length, the other variables are parameters
  DATACOL: 2 # first col is the name 

  _L = 1u;2u;5u;10u;20u;50u
  _W = 10u,100u
  _MODEL = nch

There are more possible keywords, cf. L<DATAFILE DESCRIPTION>.

=item 3. Now run synsim

  ./synsim -p -i -v -f IDvsL.data

  -p to create plots
  -i means interactive, so the plots are displayed during simulation
  -v for verbose output
  -f because the filename is not the default name

SynSim will run 12 SPICE simulations and produce 1 plot with all results.

=item 4. Results

All results are stored in the run directory, in this case:

  circuit-IDvsL

=back

=head2 2. Simulator with command-line input and fixed output file

Normal use: simplesim -a50 -b100 -c0.7

Output is saved in out.txt.

With SynSim:

=over

=item 1. Create a template file

As simplesim does not take an input file, we create a wrapper simplesim.templ in TEMPLATES/SIMTYPE.
This file is actually a template for a simple perl script:

 system("simplesim -a_VAR1 -b_VAR2 -c_VAR3");
 system("cp out.txt $ARGV[0]");

=item 2. Create a data file (e.g. test.data)

  TITLE: simplesim test
  SIMTYPE : simplesim
  COMMAND : perl inputfile outputfile

=item 3. Now run synsim

  ./synsim -f test.data

SynSim will run without any messages and produce no plots.

=item 4. Results

All results are stored in the run directory, in this case:

  simplesim-test

=back

=head2 3. Simulator without input file, configured at compile time 

Normal use: Modify values for #if and #ifdef constants in the header file; then compile and run.

e.g.:

  vi bufsim3.h
  g++ -o bufsim3 bufsim3.cc
  ./bufsim3 > outputfile

With SynSim:

=over

=item 1. Put the source code (bufsim3.cc) in SOURCES

=item 2. Create a template file

As bufsim3 does not take an input file, we create a wrapper bufsim3.templ in TEMPLATES/SIMTYPE.
This file is actually a template for a perl script that writes the header file, compiles and runs the code:

  open(HEADER,">bufsim3.h");
  print HEADER <<"ENDH";
  #define NBUFS _NBUFS
  #define NPACKETS _NPACK
  #AGGREGATE _AGGREGATE
  ENDH
  close HEADER;

  system("g++ -o bufsim3 bufsim3.cc");
  system("./bufsim3 $ARGV[0]");

=item 3. Create a datafile (e.g. Aggregate.data)

  TITLE: bufsim3 test (_NBUFS, _NPACK) # will be substituted by the values
  SIMTYPE : bufsim3
  COMMAND : perl inputfile outputfile

=item 4. Run synsim

  ./synsim -w -v -f Aggregate.data

SynSim will run verbose and flag all variables not defined in the datafile.

=item 4. Results

All results are stored in the run directory, in this case:

  bufsim3-Aggregate

=back

=head2 4. Circuit simulator which produces binary files.

Normal use: spectre circuit.scs -raw circuit.raw

With SynSim:

=over

=item 1. Create a template file

Copy circuit.scs to TEMPLATES/SIMTYPE/circuit.templ
Replace all variable values with SynSim variable names.

=item 2. Create a data file

The .raw file is a binary file, so it should not be touched. SynSim creates output files with extension .out, and combines these with the headers etc. (cf. L<OUTPUT FILES>). By keeping the extension .raw, the simulator output files will not be touched. 

In the datafile:

  TITLE: Spectre simulation with SPF output
  EXT: .scs
  COMMAND: spectre inputfile -raw outputfile.raw > outputfile

=item 3. Run synsim

SynSim will process C<outputfile>, but not C<outputfile.raw>.

=item 4. Postprocessing

To access the binary files, you'll have to write your own postprocessing routines. Most likely they will rely on an external tool to process the binary data. The files will be found in the run directory, and have names as described in L<OUTPUT FILES>, with the extra extension .raw.

=back

=head1 TO DO

This module is still Alpha, a lot of work remains to be done to make it more user-friendly. The main tasks is to add a GUI. A prototype can be found on my web site, it is already useful but too early to include here. The next version will also make it easier to create your own postprocessing routines.

=head1 AUTHOR

Wim Vanderbauwhede <wim\x40motherearth.org>

=head1 COPYRIGHT

Copyright (c) 2000,2002-2003 Wim Vanderbauwhede. All rights reserved. This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

gnuplot L<http://www.ucc.ie/gnuplot/gnuplot.html>

=cut
