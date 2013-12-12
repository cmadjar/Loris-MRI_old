#! /usr/bin/env perl

require 5.001;
use strict;
use warnings;
use File::Copy;
use File::Path 'make_path';
use Getopt::Tabular;
use File::Basename;
use FindBin;

my $Usage = <<USAGE;

This pipeline takes CIVET GM masks and put them back into native space.

Usage $0 [options]

-help for options

USAGE
my $log_dir='/data/preventAD/data/pipelines/ASL/logs';
my $out='/data/preventAD/data/pipelines/ASL/GM_masks';
my ($list, @args);

my @args_table = (["-list","string",1,\$list, "list of CIVET directories to look for GM masks"],
["-log_dir","string",1,\$log_dir,"directory for log files"],
["-out","string",1,\$out,"directory where the native GM masks should be created"]
);

Getopt::Tabular::SetHelp ($Usage,'');
GetOptions(\@args_table,\ @ARGV,\@args) || exit 1;

# needed for log file
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
my $date=sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my $log="$log_dir/GM_creation$date.log";
open(LOG,">>$log");
print LOG "Log file, $date\n\n";

if(!$list) { print "You need to specify a file with the list of directory to analyze.\n"; exit 1;}

open(DIRS,"<$list");
my @dirs=<DIRS>;
close(DIRS);
foreach my $d(@dirs){
    chomp($d);
    my ($site,$candID,$visit,$run)=getSiteSubjectVisitIDs($d);
    next    if(!$site);
    print LOG "Site \t\tCandID \t\tVisit \t\tRun\n$site \t$candID \t\t$visit \t$run\n";

    my $outdir = $out."/".$candID."/".$visit;
    make_path($outdir,0,0755) unless -e $outdir;

    my $GM_tal = $d."/classify/".$site."_".$candID."_".$visit."_adniT1_".$run."_pve_gm.mnc";
    my $xfm_lin = $d."/transforms/linear/".$site."_".$candID."_".$visit."_adniT1_".$run."_t1_tal.xfm";

    my $GM_native = $outdir."/".$site."_".$candID."_".$visit."_adniT1_".$run."_pve_gm_native.mnc";

    my $nativeT1 = $d."/native/".$site."_".$candID."_".$visit."_adniT1_".$run."_t1.mnc";

    if (-e $GM_native){
    	print LOG "GM already in native space \n" if -e $GM_native;
	next;
    }
	
    # should use trilinear interpolation based on Claudine's aging paper
    my $cmd = "mincresample -transformation $xfm_lin -invert_transformation -like $nativeT1 -nofill -nearest_neighbour $GM_tal $GM_native";
    print LOG "Command is: $cmd \n" unless -e $GM_native;
    system($cmd) unless -e $GM_native;
}

=pod

This function extracts the site, candid and visit from the path to the ASL file given to the script.

=cut

sub getSiteSubjectVisitIDs {
    my ($d)=@_;
    if ($d=~m/\/(\d+)_([N,P][A,R][P,E][B,F][L,U]\d+)_adniT1_(\d+)/i){
        my $site="PreventAD";
        my $candID=$1;
        my $visit=$2;
	my $run=$3;
        return($site,$candID,$visit,$run);
    }else{
        return undef;
    }
}

