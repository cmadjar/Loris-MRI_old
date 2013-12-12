#! /usr/bin/env perl

require 5.001;
use strict;
use warnings;
use File::Copy;
use File::Path 'make_path';
use Getopt::Tabular;
use File::Basename;
use FindBin;
use ASL;

my $Usage = <<USAGE;

This pipeline convert files from dicom to nifti format and organize them according to DCCID/Visit_label.

Usage $0 [options]

-help for options

USAGE
my $log_dir='/Users/cmadjar/Documents/McGill/PreventAD/Scripts/ASLquantification/logs';
my $out='/Users/cmadjar/Documents/McGill/PreventAD/Transfers/ASL/ANALYSES';
my $xml_template='/Users/cmadjar/Documents/McGill/PreventAD/Scripts/ASLquantification/ASLparameters_v1.0_2013-02-27.xml';
my ($list,@args);

my @args_table = (["-list","string",1,\$list,"list of directories to look in for dicom files"],
["-log_dir","string",1,\$log_dir,"directory for log files"],
["-out","string",1,\$out,"directory where the ANALYSES should be ran"],
["-xml","string",1,\$xml_template,"xml file summarizing ASL analysis parameters"]
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
	my ($site,$candID,$visit)=ASL::getSiteSubjectVisitIDs($d);
	next    if(!$site);
	print "Site \t\tCandID \t\tVisit\n$site \t$candID \t\t$visit\n";

    my $outdir      =   $out."/".$candID."/".$visit."/mri/processed/ASLQuantification";
    my $xml_file    =   $outdir."/".basename($xml_template);
    make_path($outdir,0,0755)     unless -e $outdir;
    `cp $xml_template $xml_file`  unless -e $xml_file;

    # read the XML file with analysis' options and get the list of plugins to run
    my $xml         = new XML::Simple (KeyAttr=>[]);
    my $nldo_opt    = $xml->XMLin($xml_file);
    my @plugin_list;
    foreach my $plug (@{$nldo_opt->{plugin}}){
        push(@plugin_list,$plug->{name});
    }

    # parse the native directory for ASL files
    my $natdir = $d."/mri/native";
    opendir(NATDIR,$natdir);
    my @files;
    while(my $filename=readdir(NATDIR)){
        next if (($filename eq '.') || ($filename eq '..'));
        if ($filename!~/_ASL_/i){ 
            print "$filename is not an ASL file...\n"; 
            next;
        }
        
        # Get the names of the output files
        my ($preprocessed_flow,$preprocessed_even,$flow_eff,$even_eff,$cbf_map)=ASL::getOutputNames($filename,$outdir,$nldo_opt);
        if (-e $preprocessed_flow && -e $preprocessed_even && -e $flow_eff && -e $even_eff && -e $cbf_map)
            {print "$filename has already been processed\n"; next;}
        if (-e $preprocessed_flow || -e $preprocessed_even || -e $flow_eff || -e $even_eff || -e $cbf_map){
            print "Only part of the outputs are already present for $candID $visit \n Deleting all partial outputs...\n"; 
            print "rm $outdir/*";
        }

        # Run preprocessing and GLM on the flow series
        my $command_open     = "nldo open ".$d."/mri/native/".$filename;
        my $command_close    = "nldo close LAST";
        my $command_closeALL = "nldo close ALL";
        system($command_open);
        foreach my $plug (@plugin_list){
            next if ($plug eq "ASL Quantification");
            print "Running $plug on $candID $visit ...\n";
            my ($options)=ASL::getParameters($nldo_opt,$plug);
            my $command = "nldo run '$plug' -inputDataset LAST $options";
            system($command);
        }
        # Save and close the preprocessed images and the effect map for the flow series
        my $command_saveEffFlow="nldo save LAST $flow_eff";
        my $command_savePreprocFlow=   "nldo save LAST $preprocessed_flow";
        system($command_saveEffFlow);
        system($command_close); # close the flow map
        system($command_savePreprocFlow);
        system($command_close); # close the preprocessed map
        system($command_close); # close the flow series
        # run Spatial Filtering and GLM Time Series plugins on the even series
        foreach my $plug (@plugin_list){
            next unless ($plug eq "GLM Time Series" || $plug eq "Spatial Filtering");
            print "Running $plug on $candID $visit even series ...\n";
            my ($options)=ASL::getParameters($nldo_opt,$plug);
            my $command = "nldo run '$plug' -inputDataset LAST $options";
            system($command);
        }
        # Save and close the preprocessed images and the effect map for the even series
        my $command_saveEffEven="nldo save LAST $even_eff";
        my $command_savePreprocEven=   "nldo save LAST $preprocessed_even";
        system($command_saveEffEven);
        system($command_close);
        system($command_savePreprocEven);
        system($command_closeALL);
        # Open the even and flow maps and run ASL quantification on them
        my $command_open_flow="nldo open ".$flow_eff;
        my $command_open_even="nldo open ".$even_eff;
        system($command_open_flow);
        system($command_open_even);
        foreach my $plug (@plugin_list){
            next unless ($plug eq "ASL Quantification");
            print "Running $plug on $candID $visit even series ...\n";
            my ($options)=ASL::getParameters($nldo_opt,$plug);
            my $command = "nldo run '$plug' -m0Estimate $even_eff -deltaM $flow_eff $options";
            system($command);
            print $command."\n";
        }
        my $command_saveCBF="nldo save LAST $cbf_map";
        system($command_saveCBF);
        system($command_closeALL);
    }   
}
