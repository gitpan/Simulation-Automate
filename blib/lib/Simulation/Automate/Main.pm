package Simulation::Automate::Main;

use vars qw( $VERSION );
$VERSION = "0.9.5";

################################################################################
#                                                                              #
#  Copyright (c) 2000,2002 Wim Vanderbauwhede. All rights reserved.            #
#  This program is free software; you can redistribute it and/or modify it     #
#  under the same terms as Perl itself.                                        #
#                                                                              #
################################################################################


=headers

Module to support script for simulation automation.
The function &main() is called from the innermost loop of
SynSimLoops.pm; the latter is generated on the fly by
SynSimGen.pm.

This module is generic.

$Id: Main.pm,v 1.3 2003/04/14 15:47:37 wim Exp $

=cut

use sigtrap qw(die untrapped normal-signals
               stack-trace any error-signals); 
use strict;
use Cwd;
use FileHandle;
use Exporter;

@Simulation::Automate::Main::ISA = qw(Exporter);
@Simulation::Automate::Main::EXPORT = qw(
		     main
		     pre_run
		     run
		     post_run					
                  );

use lib '.','..';

use  Simulation::Automate::Analysis;

##################################################################################
my $simpid=undef; 
#END{
#print `ps -f | grep bufsim3| grep -v grep`;
#print STDERR "Sending SIGTERM to simulator ($simpid) from $0 ...\n";
#kill 'TERM',$simpid;
#}

sub main {

use Cwd;

my $dataset=shift; 
my $count=shift;
my $dataref=shift;
my $flagsref=shift;
my ($batch,$interactive,$nosims,$plot,$verbose,$warn)=@{$flagsref};

(my $nsims, my $simdataref)=@{$dataref};

print STDERR '#',"-" x 79, "\n" if $verbose;## Simulation run $count\n";

my %simdata=%{$simdataref};
my @results=();
my $command=$simdata{COMMAND}||'perl inputfile outputfile'; 

my $pattern=$simdata{OUTPUT_FILTER_PATTERN}|| '.*';
my $simtype=$simdata{SIMTYPE}||'';
my $dirname= "${simtype}-$dataset";

my $devtype=$simdata{DEVTYPE}||'';
my $simtitle=$simdata{TITLE};
foreach my $key (keys %simdata) {
($key!~/^_/) && next;
($simtitle=~/$key/) && do {
$simtitle=~s/$key/$key:$simdata{$key}/;
};
}
my $title="#$simtitle\n"||"#$devtype $simtype simulation\n";
my $ext=$simdata{TEMPL}||'.templ';
my $extin=$simdata{EXT}||'.pl';
my $workingdir =cwd();
chdir  "$workingdir/$dirname";

## INPUT FILE CREATION

foreach my $simn (1..$nsims) {
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
      #      print STDERR grep /$pattern/,`$commandline > simlog 2>&1`;
      #or, with a pipe:
      $simpid = open(SIM, "$commandline 2>&1 |") || die "can't fork: $!"; 
      open(LOG,">simlog");
      while (<SIM>) {
	print LOG;
	/$pattern/ && do {
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
  } # if simulations not disabled
  if($nsims>1) {
    #Postprocessing
    &egrep($pattern,"${simtype}_C${count}_${simn}.out",'>>',"${simtype}_C${count}_.out");
  }
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
&egrep($pattern, "${simtype}_C${count}_.out", '>>', "${simtype}_C$count.res");
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
my $pattern= '.*';
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

$pattern=$simdata{OUTPUT_FILTER_PATTERN}|| '.*';
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
      #      print STDERR grep /$pattern/,`$commandline > simlog 2>&1`;
      #or, with a pipe:
      $simpid = open(SIM, "$commandline 2>&1 |") || die "can't fork: $!"; 
      open(LOG,">simlog");
      while (<SIM>) {
	print LOG;
	/$pattern/ && do {
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
  } # if simulations not disabled
  if($nsims>1) {
    #Postprocessing
    &egrep($pattern,"${simtype}_C${count}_${simn}.out",'>>',"${simtype}_C${count}_.out");
  }
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

#Postprocessing after sweep
&egrep($pattern, "${simtype}_C${count}_.out", '>>', "${simtype}_C$count.res");
chdir "$workingdir";

return \@results; # PostProcessors are only called after &main() exits.

} # END of post_run()
#==============================================================================

print STDERR "\n","#" x 80,"\n#\t\t\tSynSim simulation automation tool\n#\n#  (c) Wim Vanderbauwhede 2000,2002-2003. All rights reserved.\n#  This program is free software; you can redistribute it and/or modify it\n#  under the same terms as Perl itself.\n#\n","#" x 80,"\n";

#-------------------------------------------
# SUBROUTINES
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
foreach my $key (keys %simdata) {

  ($key!~/^_/) && next;
  if(@{$simdata{$key}}==1) {
    $exprdata{$key}=&check_for_expressions(\%simdata,$key,$nsim);
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
			  $line =~ s/$key(?!\w)/$exprdata{$key}/g;
#			  print STDERR "# $key = ",$simdata{$key}->[0],"\n" if $warn;
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
my @maybevars=split(/[\ \*\+\-\/\^\(\)\[\]\{\}\?\:\=]+/,$expr);
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
