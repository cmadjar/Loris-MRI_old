#! /usr/bin/env perl

require 5.001;
use strict;
use warnings;
use File::Copy;
use File::Path 'remove_tree';
use File::Temp qw/ tempdir /;
use Getopt::Tabular;
use File::Basename;
use FindBin;

my $Usage = <<USAGE;

This pipeline convert files from dicom to nifti format and organize them according to DCCID/Visit_label.

Usage $0 [options]

-help for options

USAGE
my $outdir      = '/data/preventAD/data/pipelines/Task/DATA';
my $log_dir     = '/data/preventAD/data/pipelines/Task/logs';
my $converter   = 'dcm2nii';
my $optionfile  = '/home/lorisdev/.dcm2nii/dcm2nii.ini';
my ($list,@args);

my @args_table  = (["-list",     "string", 1, \$list,        "list of directories to look in for tarchives including full path" ],
                  ["-o",        "string", 1, \$outdir,      "base output dir to put the converted files"                       ],
                  ["-log_dir",  "string", 1, \$log_dir,     "directory for log files"                                          ],
                  ["-converter","string", 1, \$converter,   "converter to be used"                                             ],
                  ["-option",   "string", 1, \$optionfile,  "Option file be used with the converter"                           ]
                 );

Getopt::Tabular::SetHelp ($Usage,'');
GetOptions(\@args_table,\ @ARGV,\@args) || exit 1;

# needed for log file
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)    = localtime(time);
my $date    = sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my $log     = "$log_dir/Conversion$date.log";
open(LOG,">>$log");
print LOG "Log file, $date\n\n";

open(TARS,"<$list");
my @tars    = <TARS>;
close(TARS);

# create the temp dir
my $template    = "TarConvert-$hour-$min-XXXXXX"; # for tempdir

foreach my $tarchive (@tars) {
    chomp ($tarchive);

    my $TmpDir  = tempdir($template, TMPDIR => 1, CLEANUP => 1 );
    my $dcm_dir = $TmpDir . "/" . extract_tarchive($tarchive, $TmpDir);       

    my ($site,$candID,$visit)   = getSiteSubjectVisitIDs($dcm_dir);    
    next    if (!defined($site));
    print   LOG "Site is $site \t CandID is $candID \t Visit is $visit \n";
    
    #subject and visit folders creation 
    my ($candir, $visdir)   =   createOutFolders($outdir, $candID, $visit);

    my $command = $converter . " -b " . $optionfile . " -o " . $outdir . "/" . $candID . "/" . $visit . " " . $dcm_dir;
    print   LOG "\t==> Converting data for site $site, candidate $candID, visit $visit.\n" unless (<$visdir/*.nii.gz>);
    print   LOG "\t==> Data already converted.\n" if (<$visdir/*.nii.gz>);
    system($command)    unless (<$visdir/*.nii.gz>);
    
    # keep only Encoding, Retrieval, oriented MPRAGE, fieldmaps images.
    my @remove_list = glob "$visdir/AAHScout* $visdir/AXIAL* $visdir/co* $visdir/MPRAGE* $visdir/RSN* $visdir/*pCASL* $visdir/T2SAG* $visdir/*TI900*";
    remove_tree(@remove_list, {result => \my $res_list});
    if (@$res_list == 0){
        print   LOG "\t==> No files were deleted.\n";
    }else{
        print   LOG "\t==> Removed the following nifti files @$res_list.\n";
    }

    # Rename the files according to LORIS convention
    opendir(OUTDIR,$visdir);
    my $newfile;
    while(my $filename = readdir(OUTDIR)){
        next    if (($filename eq '.') || ($filename eq '..') || ($filename=~/PreventAD_/i));
        my $newname;
        if ($filename =~ /(EN3ep2d64s)(\d\d\d[a-z]\d+)/i) { 
            $newname    = "PreventAD_" . $candID . "_" . $visit . "_Encoding_" . $2 . ".nii.gz"; 
            print $newname."\n"; 
        } elsif ($filename =~ /(RETep2d64s)(\d\d\d[a-z]\d+)/i) { 
            $newname    = "PreventAD_" . $candID . "_" . $visit . "_Retrieval_" . $2 . ".nii.gz"; 
            print $newname."\n"; 
        } elsif ($filename =~ /(oMPRAGEADNIiPAT2s)(\d\d\d[a-z]\d+)/i) { 
            $newname    = "PreventAD_" . $candID . "_" . $visit . "_adniT1_" . $2 . ".nii.gz"; 
            print $newname."\n"; 
        } elsif ($filename =~ /(grefieldmappings)(\d\d\d[a-z]\d+)/i) { 
            $newname    = "PreventAD_" . $candID . "_" . $visit . "_Fieldmap_" . $2 . ".nii.gz"; 
            print $newname."\n"; 
        }        
        my $file    = $visdir . "/" . $filename;
        $newfile    = $visdir . "/" . $newname;
        print   LOG "\t==> Renaming $file to $newfile\n";
        move($file,$newfile)    or die(qq{failed to move $file -> $newfile});
    }
    close(OUTDIR);

    `rm -r $dcm_dir`;
}


sub getSiteSubjectVisitIDs {
    my ($dcm_dir)   = @_;
    if ($dcm_dir =~ m/[A-Za-z0-9]+_([0-9]+)_([N,P][A,R][P,E][B,F][L,U][0-9][0-9])/i) {
        my $site    = "PreventAD";          # only one site so far, will be changed when several sites
        my $candID  = $1;
        my $visit   = $2;
        return ($site, $candID, $visit);
    }else{
        return undef;
    }
}

# Most important function now. Gets the tarchive and extracts it so data can actually be uploaded
sub extract_tarchive {
    my ($tarchive, $tempdir)    = @_;
    print   "Extracting tarchive\n";
    `cd $tempdir ; tar -xf $tarchive`;
    opendir TMPDIR, $tempdir;
    my @tars    = grep { /\.tar\.gz$/ && -f "$tempdir/$_" } readdir(TMPDIR);
    closedir TMPDIR;
    if(scalar(@tars) != 1) {
        print   "Error: Could not find inner tar in $tarchive!\n";
        print   @tars . "\n";
        exit(1);
    }
    my $dcmtar  = $tars[0];
    my $dcmdir  = $dcmtar;
    $dcmdir     =~ s/\.tar\.gz$//;
    
    `cd $tempdir ; tar -xzf $dcmtar`;
    return ($dcmdir);
}

=pod
Function that creates the candidate and visit output folders.
=cut
sub createOutFolders {
    my ($outdir, $candID, $visit)   = @_;
       
    my $candir  = $outdir."/".$candID;
    `mkdir $candir`     unless (-d "$candir");
    my $visdir  = $candir."/".$visit;
    `mkdir $visdir`     unless (-d "$visdir");
}
