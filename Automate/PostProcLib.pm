package Simulation::Automate::PostProcLib;

use vars qw( $VERSION );
$VERSION = '0.9.3';

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

$Id: PostProcLib.pm,v 1.3 2003/01/08 12:19:38 wim Exp $

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
			   $sweepvals
			   $sweepvar
			   $normvar
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
  
  my $dataset=shift;
  $Simulation::Automate::PostProcLib::count=shift;
  my $dataref=shift;
  my $flagsref=shift;
  my $verylast=shift;
  # $Simulation::Automate::PostProcLib::verylast=shift;
  
  if($verylast!=1){
    @Simulation::Automate::PostProcLib::results=@{$verylast};
    $Simulation::Automate::PostProcLib::verylast=0;
  } else {
    @Simulation::Automate::PostProcLib::results=();
    $Simulation::Automate::PostProcLib::verylast=1;
  }

  (my $batch,$Simulation::Automate::PostProcLib::interactive,my $nosims,$Simulation::Automate::PostProcLib::plot,my $verbose)=@{$flagsref};
  my $copy_results=1;
  (my $nsims, my $simdataref,my $sweepedref,my $lastref)=@{$dataref};
  
  %Simulation::Automate::PostProcLib::simdata=%{$simdataref};

  my %sweeped=%{$sweepedref};
$Simulation::Automate::PostProcLib::sweepvals='';
foreach my $key (sort keys %sweeped) {
  $Simulation::Automate::PostProcLib::sweepvals.="${key}-".$sweeped{$key}.'-';
}
$Simulation::Automate::PostProcLib::sweepvals=~s/-$//;
  my @sweeped=sort keys %sweeped;
  my $setvar=$Simulation::Automate::PostProcLib::simdata{SETVAR}||'none';
  my $sweepval=${$Simulation::Automate::PostProcLib::simdata{$setvar}}[0];

  my %last=%{$lastref};
$Simulation::Automate::PostProcLib::last=($setvar ne 'none' && $sweepval==$last{$setvar});

  my $pattern=$Simulation::Automate::PostProcLib::simdata{OUTPUT_FILTER_PATTERN}|| '.*';
my $devtype=$Simulation::Automate::PostProcLib::simdata{DEVTYPE};
    my $ext=$Simulation::Automate::PostProcLib::simdata{TEMPL};
$Simulation::Automate::PostProcLib::sweepvar=$Simulation::Automate::PostProcLib::simdata{SWEEPVAR}||'none';
$Simulation::Automate::PostProcLib::normvar=$Simulation::Automate::PostProcLib::simdata{NORMVAR}||'none';

$Simulation::Automate::PostProcLib::datacol=$Simulation::Automate::PostProcLib::simdata{DATACOL}||1;

$Simulation::Automate::PostProcLib::simtempl=$Simulation::Automate::PostProcLib::simdata{SIMTYPE};
$Simulation::Automate::PostProcLib::dirname= "${Simulation::Automate::PostProcLib::simtempl}-$dataset";
$Simulation::Automate::PostProcLib::anatempl=$Simulation::Automate::PostProcLib::simdata{ANALYSIS_TEMPLATE};

$Simulation::Automate::PostProcLib::title=$Simulation::Automate::PostProcLib::simdata{TITLE}||"$devtype $Simulation::Automate::PostProcLib::simtempl simulation";
my $simtitle=$Simulation::Automate::PostProcLib::title;
foreach my $key (keys %Simulation::Automate::PostProcLib::simdata) {
($key!~/^_/) && next;
($simtitle=~/$key/) && do {
my $val=$Simulation::Automate::PostProcLib::simdata{$key};
my $nicekey=$make_nice{$key}{title};
my $niceval=$make_nice{$key}{$val}||join(',',@{$val});
$simtitle=~s/$key/$nicekey:\ $niceval/;
};
$Simulation::Automate::PostProcLib::title=$simtitle;
}

# XTICS, YTICS, XSTART, XSTOP, YSTART, YSTOP
$Simulation::Automate::PostProcLib::ylabel=$Simulation::Automate::PostProcLib::simdata{YLABEL}||"$Simulation::Automate::PostProcLib::title";
$Simulation::Automate::PostProcLib::xlabel=$Simulation::Automate::PostProcLib::simdata{XLABEL}||"$Simulation::Automate::PostProcLib::title";
$Simulation::Automate::PostProcLib::logscale=($Simulation::Automate::PostProcLib::simdata{LOGSCALE})?"set nologscale xy\nset logscale ".lc($Simulation::Automate::PostProcLib::simdata{LOGSCALE}):'set nologscale xy';


$Simulation::Automate::PostProcLib::sweepvartitle=$make_nice{$Simulation::Automate::PostProcLib::sweepvar}{title}||$Simulation::Automate::PostProcLib::xlabel||$Simulation::Automate::PostProcLib::sweepvar;
( $Simulation::Automate::PostProcLib::legendtitle, $Simulation::Automate::PostProcLib::legend)=@{&create_legend($Simulation::Automate::PostProcLib::sweepvals,\%make_nice)};

}

#------------------------------------------------------------------------------

sub gnuplot {
my $commands=shift;
my $persist=shift||'';
if($Simulation::Automate::PostProcLib::plot) {
open GNUPLOT,"| gnuplot $persist";
print GNUPLOT $commands;
close GNUPLOT;
}
}
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
$legendtitle.=$make_nice{$key}{title}||$key;
$legend.=$make_nice{$key}{$title{$key}}||$title{$key};
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

my $line=$firstplotline."\nplot ".join(",\\\n",@lines);
#carp "COMBINED: $line";
#die;
if($Simulation::Automate::PostProcLib::plot) {
open GNUPLOT,"| gnuplot";
print GNUPLOT $line;
close GNUPLOT;
}
open GNUPLOT,">${Simulation::Automate::PostProcLib::simtempl}-${Simulation::Automate::PostProcLib::anatempl}.gnuplot";
print GNUPLOT $line;
close GNUPLOT;

if($Simulation::Automate::PostProcLib::interactive) {
system("gv ${Simulation::Automate::PostProcLib::simtempl}-${Simulation::Automate::PostProcLib::anatempl}.ps &");
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
my $titlepart=$make_nice{$key}{title}||$key;
$legendtitle.=','.$titlepart;
my $legendpart=$make_nice{$key}{$title{$key}}||$title{$key};
$legend.=','.$legendpart;
}
$legend=~s/^,//;
$legendtitle=~s/^,//;
return [$legendtitle,$legend];
}
#------------------------------------------------------------------------------
1;
#print STDERR "#" x 80,"\n#\t\t\tSynSim simulation automation tool\n#\n#\t\t\t(C) Wim Vanderbauwhede 2002\n#\n","#" x 80,"\n\n Module SynSim::PostProcLib loaded\n\n";


