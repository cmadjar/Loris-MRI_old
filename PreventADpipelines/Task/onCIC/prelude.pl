#! /usr/bin/env perl

use strict;
use warnings;
use Getopt::Tabular;

my $Usage = <<USAGE;

This script preprocess the fieldmap images that will be used for BOLD analysis.

Usage $0 [options]

-help for options

USAGE

my $log_dir="/data/prevent_ad/scripts/logs";
my ($list,@args);

my @args_table = (["-list","string",1,\$list,"list of directories to look for Fieldmap images (candID/visit)"],
["-log_dir","string",1,\$log_dir,"directory for log files"]
);

Getopt::Tabular::SetHelp ($Usage,'');
GetOptions(\@args_table,\ @ARGV,\@args) || exit 1;

# needed for log file
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
my $date=sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my $log="$log_dir/ASLQuantification$date.log";
open(LOG,">>$log");
print LOG "Log file, $date\n\n";

if(!$list) { print "You need to specify a file with the list of directory to analyze.\n"; exit 1;}

open(DIRS,"<$list");
my @dirs=<DIRS>;
close(DIRS);
foreach my $d(@dirs){
    chomp($d);
    my ($site,$candID,$visit)=getSiteSubjectVisitIDs($d);
        next    if(!$site);
        print "Site \t\tCandID \t\tVisit\n$site \t$candID \t\t$visit\n";

    my @mag_list;
    opendir(DIR,$d);
    while(my $file=readdir(DIR)){
        next unless ($file=~/Fieldmap/m);
        my $dim=qx(fslval $d/$file dim4 );
        next unless ($dim == 2);
        push(@mag_list,$file);
    }
    my @phase_list;
    foreach my $mag (@mag_list){
        if ($mag=~/($site\_$candID\_$visit\_Fieldmap)_(\d)(\d)(\d)a(\d\d\d\d)/m){
            my $base=$1;
            my $serNb;
            if ($4 == 9) {
                my $n=$3+1; 
                $serNb=$2.$n."0";
            }else{
                my $n=$4+1;
                $serNb=$2.$3.$n;
            }
            my $end=$5+1000;
            
            my $phase=$base."_".$serNb."a".$end.".nii.gz";
            push(@phase_list,$phase);
        }
    }
    
    if ($#mag_list != $#phase_list) { print LOG "Error, there is more magnitude files than phase files for $candID $visit \n"; next;}

    my $i=0;
    while ($i<=$#mag_list){
        my $mag=$d."/".substr($mag_list[$i],0,-7);
        my $phase=$d."/".substr($phase_list[$i],0,-7);
        next unless -e ($mag.".nii.gz");
        next unless -e ($phase.".nii.gz");
        
        print "Running BET on the magnitude map \n";
        my $command="bet $mag $mag\_brain -B -f 0.5 -g 0";
        system($command);
        print "Getting (wrapped) phase in radians \n";
        my $command="fslmaths $phase -div 4095 -mul 3.14159 $phase\_rad -odt float";
        system($command);

        print "File magnitude number $i: $mag_list[$i]\n";
        print "File phase number $i: $phase_list[$i]\n";
        $i++;
    }
}

sub getSiteSubjectVisitIDs{
    my ($d)=@_;
    if ($d=~m/DATA\/(\d+)\/([N,P][A,R][P,E][B,F][L,U]\d+)/i){
        my $site="PreventAD";
        my $candID=$1;
        my $visit=$2;
        return($site,$candID,$visit);
    }else{
        return undef;
    }
}
