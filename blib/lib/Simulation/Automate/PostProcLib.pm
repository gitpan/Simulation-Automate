package Simulation::Automate::PostProcLib;

use vars qw( $VERSION );
$VERSION = "0.9.6";

################################################################################
#                                                                              #
#  Copyright (C) 2000,2002 Wim Vanderbauwhede. All rights reserved.            #
#  This program is free software; you can redistribute it and/or modify it     #
#  under the same terms as Perl itself.                                        #
#                                                                              #
################################################################################

=headers

Module to support synsim script for simulation automation.
This module contains a set of utility functions for use in the
PostProcessors.pm module.
This module is generic.

$Id: PostProcLib.pm,v 1.2 2003/09/04 09:54:19 wim Exp $

=cut

use sigtrap qw(die untrapped normal-signals
               stack-trace any error-signals); 
use strict;
use Carp;
use FileHandle;
use Exporter;
use lib '.','..';

use Simulation::Automate::Analysis;
use Simulation::Automate::Dictionary;

@Simulation::Automate::PostProcLib::ISA = qw(Exporter);
@Simulation::Automate::PostProcLib::EXPORT = qw(
			   &prepare_plot
			   &gnuplot
			   &gnuplot_combined
			   &copy_results
			   &create_legend
			   %simdata
			   $last
			   $verylast
			   $current_set_valstr
			   $results_file
 			   %current_set_vals					       
			   %sweepvals					       
			   $sweepvals					       
			   $sweepvar
			   $setvar
			   $normvar
			   $cond
			   $sweepvartitle
			   $plot
			   $interactive
			   $title
			   $datacol
			   $count
			   $simtempl
			   $anatempl
			   $dirname
			   $legend
			   $legendtitle
			  $xlabel
			  $ylabel
			  $logscale
			  $style
			  $xstart
			  $xstop
			  $ystart
			  $ystop
			  $xtics
			  $ytics
			  @results
			  );

##################################################################################


sub AUTOLOAD {
my $subref=$Simulation::Automate::PostProcLib::AUTOLOAD;
$subref=~s/.*:://;
print STDERR "
There is no script for this analysis in the PostProcLib.pm module.
This might not be what you intended.
You can add your own subroutine $subref to the PostProcLib.pm module.
";

}

#------------------------------------------------------------------------------

sub prepare_plot {
  use Cwd;
  #*&Simulation::Automate::PostProcessors::$subref(\$dataset,\$i,\$dataref1,\$flagsref,\$returnvalue,\$preprocref);
  #&prepare_plot(@args);
  my $dataset=shift;
  $Simulation::Automate::PostProcLib::count=shift;
  my $dataref=shift;
  my $flagsref=shift;
  my $verylastref=shift;

  if($verylastref!=1){
    @Simulation::Automate::PostProcLib::results=@{$verylastref};
    $Simulation::Automate::PostProcLib::verylast=0;
  } else {
    @Simulation::Automate::PostProcLib::results=();
    $Simulation::Automate::PostProcLib::verylast=1;
  }

  (my $batch,$Simulation::Automate::PostProcLib::interactive,my $nosims,$Simulation::Automate::PostProcLib::plot,my $verbose)=@{$flagsref};
  my $copy_results=1;
  #*my \$dataref1 = [\$nsims,\\\%data,\\\%sweepeddata,\\\%last];
  (my $nsims, my $simdataref,my $current_set_valsref,my $lastref)=@{$dataref};
  
  %Simulation::Automate::PostProcLib::simdata=%{$simdataref};
#current_set_vals is actually "the current values in the sweep", so current_set_vals would a better name
  my %current_set_vals=%{$current_set_valsref};
  $Simulation::Automate::PostProcLib::sweepvals='';
  foreach my $key (sort keys %current_set_vals) {
    $Simulation::Automate::PostProcLib::sweepvals.="${key}-".$current_set_vals{$key}.'-';
  }
  $Simulation::Automate::PostProcLib::sweepvals=~s/-$//;
  my @current_set_vals=sort keys %current_set_vals; # not used
  %Simulation::Automate::PostProcLib::current_set_vals=%current_set_vals;
  $Simulation::Automate::PostProcLib::current_set_valstr=$Simulation::Automate::PostProcLib::sweepvals;
  $Simulation::Automate::PostProcLib::cond=$Simulation::Automate::PostProcLib::simdata{COND}||'<1';
  my $setvar=$Simulation::Automate::PostProcLib::simdata{SETVAR}||'none';
  $Simulation::Automate::PostProcLib::setvar=$setvar;
  #  my $setvarval=${$Simulation::Automate::PostProcLib::simdata{$setvar}}[0]; # if SETVAR is defined, this would be the first value in the list for SETVAR. This is to used check if the last element in the SETVAR value list has been reached
  my $setvarval=$Simulation::Automate::PostProcLib::simdata{$setvar}->[0]; # if SETVAR is defined, this would be the first value in the list for SETVAR. This is to used check if the last element in the SETVAR value list has been reached

  my %last=%{$lastref}; # the last value in the list for every variable
  $Simulation::Automate::PostProcLib::last=($setvar ne 'none' && $setvarval==$last{$setvar}); # SETVAR is defined and the element in the value list has been reached. 

  my $pattern=$Simulation::Automate::PostProcLib::simdata{OUTPUT_FILTER_PATTERN}|| '.*';
  my $devtype=$Simulation::Automate::PostProcLib::simdata{DEVTYPE};
  my $ext=$Simulation::Automate::PostProcLib::simdata{TEMPL};
  $Simulation::Automate::PostProcLib::sweepvar=$Simulation::Automate::PostProcLib::simdata{SWEEPVAR}||'none';
  $Simulation::Automate::PostProcLib::normvar=$Simulation::Automate::PostProcLib::simdata{NORMVAR}||'none';
  $Simulation::Automate::PostProcLib::datacol=$Simulation::Automate::PostProcLib::simdata{DATACOL}||1;
  $Simulation::Automate::PostProcLib::simtempl=$Simulation::Automate::PostProcLib::simdata{SIMTYPE};
  $Simulation::Automate::PostProcLib::dirname= "${Simulation::Automate::PostProcLib::simtempl}-$dataset";
  $Simulation::Automate::PostProcLib::anatempl=$Simulation::Automate::PostProcLib::simdata{ANALYSIS_TEMPLATE};
  $Simulation::Automate::PostProcLib::results_file=$Simulation::Automate::PostProcLib::simtempl.'-'.$Simulation::Automate::PostProcLib::anatempl.'-'.$Simulation::Automate::PostProcLib::current_set_valstr.'.res';
  $Simulation::Automate::PostProcLib::title=$Simulation::Automate::PostProcLib::simdata{TITLE}||"$devtype $Simulation::Automate::PostProcLib::simtempl simulation";

  my $simtitle=$Simulation::Automate::PostProcLib::title;
  foreach my $key (keys %Simulation::Automate::PostProcLib::simdata) {
    ($key!~/^_/) && next;
    ($simtitle=~/$key/) && do {
      my $val=$Simulation::Automate::PostProcLib::simdata{$key};
      my $nicekey=$make_nice{$key}{title}||&make_nice($key);
      my $niceval=$make_nice{$key}{${$val}[0]}||join(',',@{$val});
      $simtitle=~s/$key/$nicekey:\ $niceval/;
    };
    $Simulation::Automate::PostProcLib::title=$simtitle;
}
# For Gnuplot
#XSTART, XSTOP, YSTART, YSTOP, XTICS, YTICS, YLABEL, XLABEL, LOGSCALE, STYLE,
$Simulation::Automate::PostProcLib::xstart=$Simulation::Automate::PostProcLib::simdata{XSTART}||"";
$Simulation::Automate::PostProcLib::xstop=$Simulation::Automate::PostProcLib::simdata{XSTOP}||"";
$Simulation::Automate::PostProcLib::ystart=$Simulation::Automate::PostProcLib::simdata{YSTART}||"";
$Simulation::Automate::PostProcLib::ystop=$Simulation::Automate::PostProcLib::simdata{YSTOP}||"";
$Simulation::Automate::PostProcLib::xtics=$Simulation::Automate::PostProcLib::simdata{XTICS}||"";
$Simulation::Automate::PostProcLib::ytics=$Simulation::Automate::PostProcLib::simdata{YTICS}||"";
$Simulation::Automate::PostProcLib::ylabel=$Simulation::Automate::PostProcLib::simdata{YLABEL}||"$Simulation::Automate::PostProcLib::title";
$Simulation::Automate::PostProcLib::xlabel=$Simulation::Automate::PostProcLib::simdata{XLABEL}||"$Simulation::Automate::PostProcLib::title";
$Simulation::Automate::PostProcLib::logscale=($Simulation::Automate::PostProcLib::simdata{LOGSCALE})?"set nologscale xy\nset logscale ".lc($Simulation::Automate::PostProcLib::simdata{LOGSCALE}):'set nologscale xy';
$Simulation::Automate::PostProcLib::style=$Simulation::Automate::PostProcLib::simdata{STYLE}||'';

$Simulation::Automate::PostProcLib::sweepvartitle=$Simulation::Automate::PostProcLib::xlabel||$make_nice{$Simulation::Automate::PostProcLib::sweepvar}{title}||$Simulation::Automate::PostProcLib::xlabel||$Simulation::Automate::PostProcLib::sweepvar;
($Simulation::Automate::PostProcLib::legendtitle, $Simulation::Automate::PostProcLib::legend)=@{&create_legend($Simulation::Automate::PostProcLib::sweepvals,\%make_nice)};
return [@_];
} # END of prepare_plot()

#------------------------------------------------------------------------------

sub gnuplot {
my $commands=shift;
my $persist=shift||'';
if($Simulation::Automate::PostProcLib::plot) {
open GNUPLOT,"| gnuplot $persist";
print GNUPLOT $commands;
close GNUPLOT;
}
} # END of gnuplot()
#------------------------------------------------------------------------------
sub gnuplot_combined {
my $firstplotline=shift;
my $plotlinetempl=shift;
my $col=$Simulation::Automate::PostProcLib::datacol;
#my %make_nice=%{shift(@_)};
### On the very last run, collect the results 
#1. get a list of all plot files

my @plotfiles=glob("${Simulation::Automate::PostProcLib::simtempl}-${Simulation::Automate::PostProcLib::anatempl}-*.res");

#2. create a gnuplot script 
#this should be a full script, but with room for additional feature
my @lines=();
my $legendtitle='';
my $lt=0;
foreach my $filename (@plotfiles) {
$lt++;
my $title=$filename;
$title=~s/${Simulation::Automate::PostProcLib::simtempl}-${Simulation::Automate::PostProcLib::anatempl}-//;
$title=~s/\.res//;
my %title=split('-',$title);

my $legend='';
$legendtitle='';
foreach my $key (sort keys %title) {
$legendtitle.=',';
$legendtitle.=$make_nice{$key}{title}||&make_nice($key);
$legend.=$make_nice{$key}{$title{$key}}||&make_nice($title{$key});
$legend.=',';
}
$legend=~s/,$//;
$legendtitle=~s/^,//;

my $plotline;
#carp '$plotline='.$plotlinetempl;
eval('$plotline='.$plotlinetempl);
#carp "PLOTLINE:$plotline";
push @lines, $plotline
}
$firstplotline=~s/set\s+key\s+title.*/set key title "$legendtitle"/;
my $plot="\nplot ";
if($firstplotline=~/$plot/ms){$plot=''};
my $line=$firstplotline.$plot.join(",\\\n",@lines);

if($Simulation::Automate::PostProcLib::plot) {
open GNUPLOT,"| gnuplot";
print GNUPLOT $line;
close GNUPLOT;
}
open GNUPLOT,">${Simulation::Automate::PostProcLib::simtempl}-${Simulation::Automate::PostProcLib::anatempl}.gnuplot";
print GNUPLOT $line;
close GNUPLOT;

if($Simulation::Automate::PostProcLib::interactive) {
system("ggv ${Simulation::Automate::PostProcLib::simtempl}-${Simulation::Automate::PostProcLib::anatempl}.ps &");
}
} # END of gnuplot_combined()
#------------------------------------------------------------------------------
sub copy_results {
use Cwd;
my $workingdir=cwd();
  if(not(-e "$workingdir/../../Results")) {
mkdir  "$workingdir/../../Results";
}
  if(not(-e "$workingdir/../../Results/$Simulation::Automate::PostProcLib::simtempl")) {
mkdir  "$workingdir/../../Results/$Simulation::Automate::PostProcLib::simtempl";
}

  if(not(-e "$workingdir/../../Results/$Simulation::Automate::PostProcLib::simtempl/$Simulation::Automate::PostProcLib::anatempl")) {
mkdir  "$workingdir/../../Results/$Simulation::Automate::PostProcLib::simtempl/$Simulation::Automate::PostProcLib::dataset";
}
system("cp ${Simulation::Automate::PostProcLib::simtempl}-${Simulation::Automate::PostProcLib::anatempl}.* $workingdir/../../Results/$Simulation::Automate::PostProcLib::simtempl/$Simulation::Automate::PostProcLib::dataset");

} #END of copy_results()
#------------------------------------------------------------------------------
sub create_legend {
my $title=shift;
my %make_nice=%{shift(@_)};
my %title=split('-',$title);

my $legend='';
my $legendtitle='';
foreach my $key (sort keys %title) {
my $titlepart=$make_nice{$key}{title}||&make_nice($key);
$legendtitle.=','.$titlepart;
my $legendpart=$make_nice{$key}{$title{$key}}||$title{$key};
$legend.=','.$legendpart;
}
$legend=~s/^,//;
$legendtitle=~s/^,//;
return [$legendtitle,$legend];
}
#------------------------------------------------------------------------------
sub make_nice {
my $varname=shift;
$varname=~s/^_//;
$varname=~s/_/ /g;
$varname=lc($varname);
$varname=~s/^([a-z])/uc($1)/e;
return $varname;
}
#------------------------------------------------------------------------------
1;
#print STDERR "#" x 80,"\n#\t\t\tSynSim simulation automation tool\n#\n#\t\t\t(C) Wim Vanderbauwhede 2002\n#\n","#" x 80,"\n\n Module SynSim::PostProcLib loaded\n\n";


