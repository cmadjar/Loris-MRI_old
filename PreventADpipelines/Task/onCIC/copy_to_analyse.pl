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
my $outdir="/data/prevent_ad/ANALYSES";
my ($list,@args);

my @args_table = (["-list","string",1,\$list,"list of directories to look for fMRI data (candID/visit)"],
["-log_dir","string",1,\$log_dir,"directory for log files"],
["-out","string",1,\$outdir,"directory where the data should be copied"]
);

Getopt::Tabular::SetHelp ($Usage,'');
GetOptions(\@args_table,\ @ARGV,\@args) || exit 1;

# needed for log file
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
my $date=sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my $log="$log_dir/prepareDataForAnalyses$date.log";
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

    ### create director subject and session directories in the output repertory
    mkdir("$outdir/$candID",0755) unless -e "$outdir/$candID";
    my $outsv="$outdir/$candID/$visit";
    mkdir("$outsv",0755) unless -e "$outsv";
    mkdir("$outsv/encoding",0755) unless -e "$outsv/encoding";
    mkdir("$outsv/retrieval",0755) unless -e "$outsv/retrieval";

    opendir(DIR,$d);
    while(my $file=readdir(DIR)){
        next if (($file eq '.') || ($file eq '..') || ($file=~/Fieldmap/m));
        my $outanat=$outsv."/".substr($file,0,-3);
        my $outenc3d=$outsv."/encoding/".substr($file,0,-7)."_0007.nii";
        my $outret3d=$outsv."/retrieval/".substr($file,0,-7)."_0007.nii";
        if ($file=~/Encoding/m){
            next if (-e "$outenc3d");
            #copy the encoding file
            my $copy="cp $d/$file $outsv/encoding/$file";
            system($copy) unless ((-e "$outsv/encoding/$file")||(-e "$outenc3d.gz"));
            # split the encoding file
            my $basename=$outsv."/encoding/".substr($file,0,-7)."_";
            my $split="fslsplit $outsv/encoding/$file $basename";
            system($split) unless (-e "$outenc3d.gz");
            # remove the 4d encoding file and the first 5 volumes
            my $rm="rm $outsv/encoding/$file $outsv/encoding/*_0000.nii.gz $outsv/encoding/*_0001.nii.gz $outsv/encoding/*_0002.nii.gz $outsv/encoding/*_0003.nii.gz $outsv/encoding/*_0004.nii.gz";
            system($rm) if ((-e "$outsv/encoding/$file")&&(-e "$outenc3d.gz"));
            my $gunzip="gunzip -r $outsv/encoding/*";
            system($gunzip) if (-e "$outenc3d.gz");
        }
        if ($file=~/Retrieval/m){
            next if (-e "$outret3d");
            #copy the retrieval file
            my $copy="cp $d/$file $outsv/retrieval/$file";
            system($copy) unless ((-e "$outsv/retrieval/$file")||(-e "$outret3d.gz"));
            # split the retrieval file
            my $basename=$outsv."/retrieval/".substr($file,0,-7)."_";
            my $split="fslsplit $outsv/retrieval/$file $basename";
            system($split) unless (-e "$outret3d.gz");
            # remove the 4d retrieval file and the first 5 volumes
            my $rm="rm $outsv/retrieval/$file $outsv/retrieval/*_0000.nii.gz $outsv/retrieval/*_0001.nii.gz $outsv/retrieval/*_0002.nii.gz $outsv/retrieval/*_0003.nii.gz $outsv/retrieval/*_0004.nii.gz";
            system($rm) if ((-e "$outsv/retrieval/$file")&&(-e "$outret3d.gz"));
            my $gunzip="gunzip -r $outsv/retrieval/*";
            system($gunzip) if (-e "$outret3d.gz");
        }
        if ($file=~/adniT1/m){
            next if (-e "$outanat");
            my $copy="cp $d/$file $outsv/$file";
            system($copy) unless (-e "$outsv/$file");
            my $gunzip="gunzip -r $outsv/*";
            system($gunzip);
        }
        `chmod -R g=rwx $outsv`;
    }
    closedir(DIR);
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

