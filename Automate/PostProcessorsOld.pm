package Simulation::Automate::PostProcessors;

use vars qw( $VERSION );
$VERSION = "1.0.0";

################################################################################
#                                                                              #
#  Copyright (C) 2000,2002-2003 Wim Vanderbauwhede. All rights reserved.       #
#  This program is free software; you can redistribute it and/or modify it     #
#  under the same terms as Perl itself.                                        #
#                                                                              #
################################################################################

=headers

Module to support SynSim simulation automation tool.
This module contains all subroutines needed for postprocessing of the simulations results. 
Some routines are quite generic, but most are specific to the type of simulation.

$Id: PostProcessors.pm,v 1.2 2003/09/04 09:54:19 wim Exp $

=cut

use strict;
use Cwd;
use Carp;
use lib '.','..';

use Simulation::Automate::Analysis;
use Simulation::Automate::PostProcLib;
##################################################################################
# Three generic routines are provided:
# SweepVar: to make a sweep over one variable while using any number of parameters
# ErrorFlags: 
# Histogram: to create simple histograms

#------------------------------------------------------------------------------
# This is a very generic module to generate plots from any sweep 

sub SweepVar {
my @args=@_;
my $extra_args_ref=&prepare_plot(@args);
my @extra_args=@{$extra_args_ref};
#@extra_args may only contain a subref 
my $subref=(@extra_args==1)?$extra_args[0]:0;
my $plotstyle=($plotstyle ne 'linespoints')?$plotstyle:'linespoints lw 4 ps 2';
(!@{$simdata{$normvar}})&&(${$simdata{$normvar}}[0]=1);

#The right way is:
my $norm=(@{$simdata{$normvar}}>1)?$current_set_vals{$normvar}:${$simdata{$normvar}}[0];

my $col=$datacol+1;

my @sweepvarvals=@{$simdata{$sweepvar}};

#hook for preprocessing routine
if($subref) {
&{$subref}("${simtempl}_C$count.res");
#NEW02072003#&{$subref}($results_file_name);
}

#this is to combine the values for different buffers into 1 file

if($verylast==0) {
# create the header (basically, only comments)
#open(HEAD,">$results_file_name");
my $resheader='';
open(IN,"<${simtempl}_C$count.res");
#NEW02072003#open(IN,"<$results_file_name");

while(<IN>) {
/\#/ && !/Parameters|$sweepvar/ && do {
#print HEAD $_
$resheader.=$_;
};
}
close IN;
open(HEAD,">$results_file_name");
print HEAD $resheader;
close HEAD;
# now add the simulation results. The difference with ${simtempl}_C$count.res
# is that the value of $sweepvar is added as the first column.
my $i=0;
foreach my $sweepvarval ( @sweepvarvals ) {
open(RES,">>${simtempl}-${anatempl}-${current_set_str}.res");
print RES "$sweepvarval\t$results[$i]";
close RES;
$i++;
}

#hook for preprocessing routine
if($subref) {
&{$subref}($results_file_name);
}
if($last) {

if($interactive) {

foreach my $sweepvarval ( @sweepvarvals ) {
#create the header
my $newsweepvals=$current_set_str;

my $gnuplotscript=<<"ENDS";
set terminal X11

$logscale
#set xtics 16
#set mxtics 2
set grid xtics ytics mxtics mytics

set key right top box 
set key title "$legendtitle" 
set key box

set title "$title" "Helvetica,14"
set xlabel "$sweepvartitle"
set ylabel "$ylabel"

plot '${simtempl}-${anatempl}-$newsweepvals.res'  using (\$1*1):$col title "$legend"  with ${plotstyle}
!sleep 1
ENDS

&gnuplot($gnuplotscript);
}
}
} # if last

} else {
### On the very last run, collect the results into one nice plot

#this is very critical. The quotes really matter!
# as a rule, quotes inside gnuplot commands must be escaped

my $plotlinetempl=q["\'$filename\' using (\$1*1):(\$_DATACOL/_NORM) title \"$legend\" with _PLOTSTYLE"];
if($normvar eq $sweepvar){$norm = '\$1'}
$plotlinetempl=~s/_NORM/$norm/;
$plotlinetempl=~s/_DATACOL/$col/;
$plotlinetempl=~s/_PLOTSTYLE/$plotstyle/;

my $xtics=2;#change later
my $firstplotline=<<"ENDH";
set terminal postscript landscape enhanced  color solid "Helvetica" 14
set output "${simtempl}-${anatempl}.ps"

$logscale

#set xtics $xtics
#set mxtics 2
set grid xtics ytics mxtics mytics

set key right top box 
set key title "$legendtitle" 

set title "$title" "Helvetica,18"
set xlabel "$sweepvartitle" "Helvetica,16"
set ylabel "$ylabel" "Helvetica,16"

ENDH

&gnuplot_combined($firstplotline,$plotlinetempl);
}

} #END of SweepVar()

#------------------------------------------------------------------------------
# This is a very generic module to generate plots from any sweep 

sub PlotXYfromPoints {

&prepare;
#&prepare_plot;

my @sweepvarvals=@{$simdata{$sweepvar}};

#this is to combine the values for different buffers into 1 file

if($verylast==0) {
# create the header (basically, only comments)
my $resheader='';
open(IN,"<$results_file_name");

while(<IN>) {
/\#/ && !/Parameters|$sweepvar/ && do {
#print HEAD $_
$resheader.=$_;
};
}
close IN;

open(HEAD,">$results_file_name");
print HEAD $resheader;
close HEAD;
# now add the simulation results. The difference with ${simtempl}_C$count.res
# is that the value of $sweepvar is added as the first column.
my $i=0;
foreach my $sweepvarval ( @sweepvarvals ) {
open(RES,">>$results_file_name");
print RES "$sweepvarval\t$results[$i]";
close RES;
$i++;
}

} else {
### On the very last run, collect the results into one nice plot
$ycol++;
&gnuplot_combined($ycol);
}

} #END of PlotXYfromPoints

#------------------------------------------------------------------------------
sub PlotXYfromRange {
  my @args=@_;
  my @extra_args=@{&prepare_plot(@args)};
  my $subref=((@extra_args>=1) && $extra_args[0])?$extra_args[0]:0;

#hook for preprocessing routine
if($subref) {
&{$subref}();
}

if($verylast) {
### On the very last run, collect the results into one nice plot

&gnuplot_combined();
}

} #END of PlotXYfromRange()

#------------------------------------------------------------------------------
sub ErrorFlags { 
my @args=@_;

my $extra_args_ref=&prepare_plot(@args);
my @extra_args=@{$extra_args_ref};
my $subref=(@extra_args==1)?$extra_args[0]:0;

(!@{$simdata{$normvar}})&&(${$simdata{$normvar}}[0]=1);
#my $norm=(@{$simdata{$normvar}}>1)?${$simdata{$normvar}}[$count]:${$simdata{$normvar}}[0];
my $norm=(@{$simdata{$normvar}}>1)?$current_set_vals{$normvar}:${$simdata{$normvar}}[0];
my $sweepvarval=$simdata{$sweepvar}[0];

#this is to combine the values for different buffers into 1 file
#It's plain wrong: sweepvar is not part of the set vars
#my $current_set_vals_nosweepvar=$current_set_str;
#$current_set_vals_nosweepvar=~s/\-*$sweepvar\-[\d\.]+//;
#$current_set_vals_nosweepvar=~s/^\-*//;

#hook for preprocessing routine
if($subref) {
&{$subref}("${simtempl}_C$count.res");
#NEW02072003#&{$subref}($results_file_name);
}

if($verylast==0) {
  
  use File::Copy;
# with the new names, this will be obsolete
  copy "${simtempl}_C$count.res","${simtempl}-${anatempl}-$current_set_str.res";
  if($last) {
    if($interactive) {
      my $gnuplotscript=<<"ENDS";
set terminal X11

$logscale
#set xtics 16
#set mxtics 2
set grid xtics ytics mxtics mytics

set key right top box 
set key title "$legendtitle" 
set key box

set title "$title" "Helvetica,14"
set xlabel "$sweepvartitle"
set ylabel "$ylabel"

plot '${simtempl}-${anatempl}-$current_set_str.res' notitle with yerrorbars, '${simtempl}-${anatempl}-$current_set_str.res'  title "$legend" with lines
!sleep 1
ENDS

      &gnuplot($gnuplotscript);
    } # if interactive (old meaning of interactive, obsolete)
  } # if last
} else { #very last run

## With NRUNS, we must wait until the very last run to calc the error flags.
# Get all results files.
my @allresfiles=glob("${simtempl}-${anatempl}-*.res");
my %allresfiles=();
foreach my $resfile (@allresfiles) {
$resfile!~/NRUNS/ && next;
my $resfilenorun=$resfile;
$resfilenorun=~s/__NRUNS-\d+/__NRUNS-/;
$allresfiles{$resfilenorun}=1;
}

my $nruns=$simdata{'NRUNS'};
## Loop over all result files 
foreach my $resfile (keys %allresfiles) {
## For each of these, loop over all runs

  my @allruns=();
  my $allpoints=0;
  foreach my $run (1..$nruns) {
    my $thisrun=$resfile;
    $thisrun=~s/__NRUNS-/__NRUNS-$run/;
    open(RES,"<$thisrun");
    my $i=0;
    while(<RES>) {
      /^#/ && next;
      /^\s*$/ && next;
      $allruns[$run][$i]=$_;
      $i++;
    }
    $allpoints=$i;
    close RES;
    unlink "$thisrun"; # This is quite essential, otherwise it will be included in the plot
  }
  my $sweepvalsnorun=$resfile;
  $sweepvalsnorun=~s/__NRUNS-\d*//;
  $sweepvalsnorun=~s/\-\-/\-/g;
  $sweepvalsnorun=~s/\-$//;

###Get header info. This is of course only fully correct for the last run;
###but we use this mainly for the names of the parameters.
### The right thing is to have SynSim use the "long" names from the start. This would make everything easier.
#my @header=();
#open(RES,"<${simtempl}_C$count.res")||carp "$!";
#while(<RES>) {
#/^\#/ && do {push @header,$_};
#}
#close RES;

open(STAT,">$sweepvalsnorun");
#foreach my $line (@header) {
#  if($line!~/NRUNS/){
#print STAT $line;
#}
#}

foreach my $i (0..$allpoints-1) {
open(TMP,">tmp$i.res");
  foreach my $run (1..$nruns) {
$allruns[$run][$i]=~s/^\d+\s+//;
print TMP $simdata{$sweepvar}->[$i],"\t",$allruns[$run][$i];
}
close TMP;
# calc average after every $count

my $par='PARAM';
my %stats=%{&calc_statistics("tmp$i.res",[$par, $datacol])};
unlink "tmp$i.res";
my $avg=$stats{$par}{AVG}/$norm;
my $stdev=$stats{$par}{STDEV}/$norm;
#Parameter should be NSIGMAS, user can choose. As it is a postprocessing par, the syntax is 'NSIGMAS : 1.96'
my $nsigmas=$simdata{NSIGMAS}||1.96;
my $minerr=$avg-$nsigmas*$stdev; # 2 sigma = 95% MAKE THIS A PARAMETER! CONFIDENCE
my $maxerr=$avg+$nsigmas*$stdev; # 2 sigma = 95%

print STAT $simdata{$sweepvar}->[$i],"\t$avg\t$minerr\t$maxerr\n";
}
close STAT;
} # all resfiles

### On the very last run, collect the results into one nice plot

#this is very critical. The quotes really matter!
# as a rule, quotes inside gnuplot commands must be escaped

my $plotlinetempl=q("\'$filename\' notitle with yerrorbars lt $lt, \'$filename\' title \"$legend\" with lines lt $lt");


my $firstplotline=<<"ENDH";
set terminal postscript landscape enhanced  color solid "Helvetica" 12
set output "${simtempl}-${anatempl}.ps"

$logscale

#set xtics 16
#set mxtics 2
set grid xtics ytics mxtics mytics

set key right top box 
set key title "$legendtitle" 

set title "$title" "Helvetica,14"
set xlabel "$sweepvartitle"
set ylabel "$ylabel"

ENDH

&gnuplot_combined($firstplotline,$plotlinetempl);
}

} #END of ErrorFlags()

#------------------------------------------------------------------------------

sub Histogram {

my @args=@_;

my $extra_args_ref=&prepare_plot(@args);
my @extra_args=@{$extra_args_ref};
my $subref=(@extra_args==1)?$extra_args[0]:0;

my $plotstyle=($plotstyle ne '')?$plotstyle:'boxes';
my $sweepvarval=${$simdata{$sweepvar}}[0]; # used for nbins?!
my $nbins=$simdata{NBINS}||20;
my $binwidth=$simdata{BINWIDTH}||1;
my $min=0;
my $max=$min+$nbins*$binwidth;
my $par='DATA';#must be "LOG" for log plot
my $log=''; #must be 'log' for log plot
#carp "LOGSCALE: $logscale\n";
my @logscale=split("\n",$logscale);
if($logscale[1]=~/x/i) {
$xstart=($xstart&&$xstart>0)?log($xstart)/log(10):'';
$xstop=($xstart&&$xstop>0)?log($xstop)/log(10):'';
  $logscale[1]=~s/x//i;
  $logscale="$logscale[0]\n$logscale[1]\n";
  $par='LOG';#'DATA';#must be "LOG" for log plot
  $log='log'
}
#carp "LOGSCALE: $logscale\n";

#hook for preprocessing routine
if($subref) {
&$subref("${simtempl}_C$count.res");
#NEW02072003#&{$subref}($results_file_name);
}

  if($verylast==0) {
#my %hists=%{&build_histograms("${simtempl}_C$count.res",[$par,$datacol],$title,$log,$sweepvarval)};
my %hists=%{&build_histograms("${simtempl}_C$count.res",[$par,$datacol],$title,$log,$nbins,$min,$max)};
#NEW02072003#my %hists=%{&build_histograms($results_file_name,[$par,$datacol],$title,$log,$nbins,$min,$max)};

#system("grep '#' ${simtempl}_C$count.res > ${simtempl}-${anatempl}-$current_set_str.res");
&egrep('#',"${simtempl}_C$count.res",'>',"${simtempl}-${anatempl}-$current_set_str.res");

#NEW02072003#&egrep('#',$results_file_name,'>',"tmp$results_file_name");
#NEW02072003#rename "tmp$results_file_name",$results_file_name;

open HIST,">>${simtempl}-${anatempl}-$current_set_str.res";
foreach my $pair (@{$hists{$par}}) {
print HIST $pair->{BIN},"\t",$pair->{COUNT},"\n";
}
close HIST;
if($interactive) {
#&gnuplot( "plot '${simtempl}-${anatempl}-$current_set_str.res' with $plotstyle\n\!sleep 1\n");
}
} else {
my $plotlinetempl=q("\'$filename\' title \"$legend\" with ).$plotstyle.q(");

my $firstplotline=<<"ENDH";
set terminal postscript landscape enhanced  color solid "Helvetica" 12
set output "${simtempl}-${anatempl}.ps"

$logscale

#set xtics 2
#set mxtics 2
set grid xtics ytics mxtics mytics

set key right top box 
set key title "$legendtitle" 

set title "$title" "Helvetica,14"
set xlabel "$sweepvartitle"
set ylabel "$ylabel"

plot [$xstart:$xstop]\\
ENDH

&gnuplot_combined($firstplotline,$plotlinetempl);

}


} #END of Histogram()

#------------------------------------------------------------------------------
# SweepVarCond: we sweep SWEEPVAR, the set is SETVAR, the final plot is (SWEEPVAR for COND) vs SETVAR
# Sweep a variable until a condition is met, then save the result; then maybe skip all other values in sweep; and later maybe allow to iterate to refine solution.
my %condval=();

sub SweepVarCondOrig {
  my @args=@_;
  my $extra_args_ref=&prepare_plot(@args);
  my @extra_args=@{$extra_args_ref};
  my $subref=(@extra_args==1)?$extra_args[0]:0;
  my $plotstyle=($plotstyle ne '')?$plotstyle:'linespoints';

  (!$simdata{$normvar} || !@{$simdata{$normvar}})&&(${$simdata{$normvar}}[0]=1);

  my $norm=(@{$simdata{$normvar}}>1)?$current_set_vals{$normvar}:${$simdata{$normvar}}[0];
  my $col=$datacol+1;
  my $notsetvarstr=$current_set_str;
  $notsetvarstr=~s/$setvar\-[\w\.]+//;
  $notsetvarstr=~s/^\-//;
#WV 17072003: Not sure about this ...
  $notsetvarstr=~s/\-\-/\-/g;
  my @sweepvarvals=@{$simdata{$sweepvar}};

#hook for preprocessing routine
#This is stupid. We don't use the results file! We use @results!
#So we must dump @results to a temp file, say 'rawdata', and modify that file.
#Or we must work straight on @results!
if($subref) {
&{$subref}("${simtempl}_C$count.res");
#NEW02072003#&{$subref}($results_file_name);
}

  if($verylast==0) { # The DOE is not finished yet
    my $condition_met=0;
    my $i=0;
    foreach my $sweepvarval ( @sweepvarvals ) { # @sweepvarvals and @results have the same length
      my @line=split(/\s+/,$results[$i]);
      $i++;
      my $value=$line[$datacol-1];
      if( !$condition_met && eval("$value$cond")) {
	$condition_met=1;
	my $setvarval=$current_set_vals{$setvar};
	push @{$condval{$notsetvarstr}},"$setvarval $sweepvarval";
      }
    } # all results for current sweep

    if ($last) { # The X-axis sweep for the current set of parameters is finished.
      foreach my $valstr (keys %condval) {
	# create the header (basically, only comments)
	my $resheader='';
	open(IN,"<${simtempl}_C$count.res");
	#NEW02072003#open(IN,"<$results_file_name");
	while(<IN>) {
	  /\#/ && !/Parameters|$sweepvar/ && do {
	    #print HEAD $_
	    $resheader.=$_;
	  };
	}
	close IN;
	open(HEAD,">${simtempl}-${anatempl}-${valstr}.res");
	print HEAD $resheader;
	close HEAD;
	
	# add values
	open(RES,">>${simtempl}-${anatempl}-${valstr}.res");
	foreach my $line (@{$condval{$valstr}}) {
	  print RES "$line\n";
	}
	close RES;
      }
    } # if last
  } else { ### On the very last run, collect the results into one nice plot
    
    # Syntax of next line is very critical. The quotes really matter!
    # as a rule, quotes inside gnuplot commands must be escaped
    my $plotlinetempl=q("\'$filename\' using (\$1*1):(\$2*1) title \"$legend\" with ).$plotstyle.q(");
    if($normvar eq $sweepvar){$norm = '\$1'}
    $plotlinetempl=~s/_NORM/$norm/;
    $plotlinetempl=~s/_DATACOL/$col/;

    my $xtics=2;#change later
    my $firstplotline=<<"ENDH";
set terminal postscript landscape enhanced  color solid "Helvetica" 14
set output "${simtempl}-${anatempl}.ps"

$logscale

#set xtics $xtics
#set mxtics 2
set grid xtics ytics mxtics mytics

set key right top box 
set key title "$legendtitle" 

set title "$title" "Helvetica,18"
set xlabel "$sweepvartitle" "Helvetica,16"
set ylabel "$ylabel" "Helvetica,16"

ENDH

    &gnuplot_combined($firstplotline,$plotlinetempl);
  }

} #END of SweepVarCondOrig()
#------------------------------------------------------------------------------

sub SweepVarCond {
#my @args=shift;
#print 'ARGS:',join(':',@args),"\n";
#  if($_[-1]==2){
#print "EVERY_SWEEP_VAL\n";
#  } else {
  &prepare_plot;
# For every corner in the DOE:
# The SETVAR (or XVAR) must be removed from the set, because we plot the results as a function of it 
  my $notsetvarstr=$current_set_str;
  $notsetvarstr=~s/$setvar\-\-*[\w\.]+//;
  $notsetvarstr=~s/^\-//;

  #The values of the conditional variable
  my @condvarvals=@{$simdata{$condvar}};

  # remove the original results file, but first make a copy for the header
  if(not -e "header.tmp") {
    use File::Copy;
    copy("${simtempl}-${anatempl}-${current_set_str}.res","header.tmp");
  }
  unlink "${simtempl}-${anatempl}-${current_set_str}.res";

 if(not $verylast) { # The DOE is not finished yet 
#  if($verylast==0) { # The DOE is not finished yet
    my $condition_met=0;
    my $i=0;
    #This is the core routine to check the condition
    foreach my $condvarval ( @condvarvals ) { # @condvarvals and @results have the same length
      my @line=split(/\s+/,$results[$i]);
      $i++;
      my $value=$line[$datacol-1];
      if( !$condition_met && eval("$value$cond")) {
	$condition_met=1;
	my $setvarval=$current_set_vals{$setvar};
	push @{$condval{$notsetvarstr}},"$setvarval $condvarval";
      }
    } # all results for current sweep

    if ($last) { # The X-axis sweep for the current set of parameters is finished.

	# create the header (basically, only comments)
	my $resheader='';
	open(IN,"<header.tmp");
	while(<IN>) {
	  /\#/ && !/Parameters|$condvar/ && do {
	    #print HEAD $_
	    $resheader.=$_;
	  };
	}
	close IN;

	foreach my $valstr (keys %condval) {
	  open(HEAD,">${simtempl}-${anatempl}-${valstr}.res");
	  print HEAD $resheader;
	  close HEAD;
	
	  # add values
	  open(RES,">>${simtempl}-${anatempl}-${valstr}.res");
	  foreach my $line (@{$condval{$valstr}}) {
	    print RES "$line\n";
	  }
	  close RES;
      }
    } # if last
  } else { ### On the very last run, collect the results into one nice plot
    $ycol++;
    &gnuplot_combined($ycol);
  }
#}
} #END of SweepVarCond()
#------------------------------------------------------------------------------

sub None {
}
#==============================================================================
#
# Routines for pre-processing of results 
# All these routines modify the @results array, which is the raw data from the simulator in a line-by-line array
#
sub show_results {
print STDERR "RESULTS:\n";
  for my $line (@results){
print STDERR $line;
}
print STDERR "-" x 78;
print STDERR "\n";
}
#------------------------------------------------------------------------------
sub get_train_lengths {
my $resultsfile=shift;
my $nports=$simdata{_NPORTS}->[0];

my $prevdest=0;
my @train_length=();

foreach my $dest (0..$nports-1) {
  $train_length[$dest]=0;
}

foreach my $line (@results){
if($line!~/^DEST/){
print TMP $line;
} else {
  chomp(my $dest=$line);
  $dest=~s/^.*\s+//;
  if($dest == $prevdest) {
    $train_length[$dest]++;
  } else {
    chomp $line;
    $line=~s/\d+$//;
    print TMP "$_\t",$train_length[$prevdest],"\n";
    foreach my $dest (0..$nports-1) {
      $train_length[$dest]=0;
    }
    $train_length[$dest]++;
    $prevdest=$dest;
  }
}
}

}
#==============================================================================
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

sub AUTOLOAD {
my $subref=$Simulation::Automate::PostProcessors::AUTOLOAD;
$subref=~s/.*:://;
print STDERR "
There is no script for the analysis $subref in the PostProcessors.pm module.
This might not be what you intended.
You can add your own subroutine $subref to the PostProcessors.pm module.
";

}
#------------------------------------------------------------------------------
1;
#print STDERR "#" x 80,"\n#\t\t\tSynSim simulation automation tool\n#\n#\t\t\t(C) Wim Vanderbauwhede 2002\n#\n","#" x 80,"\n\n Module PostProcessors loaded\n\n";


