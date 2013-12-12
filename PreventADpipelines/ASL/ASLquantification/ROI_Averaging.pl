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
#my $xml_template='/Users/cmadjar/Documents/McGill/PreventAD/Scripts/ASLquantification/ASLparameters_v1.0_2013-02-27.xml';
my ($list,@args);

my @args_table = (["-list","string",1,\$list,"list of directories to look in for dicom files"],
["-log_dir","string",1,\$log_dir,"directory for log files"],
["-out","string",1,\$out,"directory where the ANALYSES should be ran"],
["-xml","string",1,\$xml_template,"xml file summarizing ASL analysis parameters"]
);

Getopt::Tabular::SetHelp ($Usage,'');
GetOptions(\@args_table,\ @ARGV,\@args) || exit 1;




#nldo run "ROI Averaging" -lowerThreshold 0.5 -maskDataset /Users/cmadjar/Documents/McGill/PreventAD/Transfers/ASL/GM_masks/122650/PREBL00/PreventAD_122650_PREBL00_adniT1_001_pve_gm_native_resampled.mnc -upperThreshold 1.5 -targetDataset /Users/cmadjar/Documents/McGill/PreventAD/Transfers/ASL/ANALYSES/122650/PREBL00/mri/processed/ASLQuantification/PreventAD_122650_PREBL00_ASL_001-MC-flow-SM-eff-cbf.mnc  -maskOperation "Lower Threshold" +roiSignalAsText 1
