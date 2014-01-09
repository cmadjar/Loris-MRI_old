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
my $outdir      = '/data/preventAD/data/pipelines/INDI/MRI/DATA';
my $log_dir     = '/data/preventAD/data/pipelines/INDI/logs';
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

    ## Step 1: extract dicom tarchive in tmp directory
    my $TmpDir  = tempdir($template, TMPDIR => 1, CLEANUP => 1 );
    my $dcm_dir = $TmpDir . "/" . extract_tarchive($tarchive, $TmpDir);       

    ## Step 2: get Subject and Visit IDs from the extracted dicom folder
    my ($candID,$visit)   = &getSubjectVisitIDs($dcm_dir);    
    next    if ((!defined($candID)) || (!defined($visit)));
    print   LOG "CandID is $candID \t Visit is $visit \n";

    ## Step 3: determine session number based on visit_label
    my ($session)   = &getSessionNb($visit);
    
    ## Step 4: create subject and visit output folders (which will contain the nifti files) 
    my ($cand_out_dir, $session_out_dir)  = &createOutFolders($outdir, $candID, $session);

    ## Step 5:check if nifti files already exists
    my ($already_converted) = &checkFilesExist($session_out_dir);
    next if ($already_converted == 2); # files were already converted and organized according to the INDI organization
    
    # Step 6: dcm2nii conversion that will keep only resting state and anat files
    &convert2nii($converter, $optionfile, $session_out_dir, $candID, $visit, $dcm_dir) unless ($already_converted);

    # Step 7: Determine output file names and scan numbers into a hash ($files)
    my ($files) = &determineFileNames($session_out_dir);

    # Step 8: If multiple anat files, determine order of the files and insert them into the hash $files
    &determineAnatOrder($files);

    # Step 9: Move filenames according to INDI data organization
    &moveNiiFiles($files, $session_out_dir);

#    `rm -r $TmpDir`;
}

exit 0;


#############
# Functions #
#############
sub getSubjectVisitIDs {
    my ($dcm_dir)   = @_;

    if ($dcm_dir =~ m/[A-Za-z0-9]+_([0-9]+)_([N,P][A,R][P,E][B,F][L,U][0-9][0-9])/i) {
        my $candID  = $1;
        my $visit   = $2;
        return ($candID, $visit);
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
       
    my $cand_out_dir    = $outdir."/".$candID;
    `mkdir $cand_out_dir`     unless (-d "$cand_out_dir");
    my $session_out_dir   = $cand_out_dir."/".$visit;
    `mkdir $session_out_dir`     unless (-d "$session_out_dir");

    return ($cand_out_dir, $session_out_dir);
}

=pod
Function to rename nifti files according to LORIS convention.
=cut
sub determineFileNames {
    my ($session_out_dir)    = @_;

    opendir(OUTDIR,$session_out_dir);
    my @entries = readdir(OUTDIR);
    close(OUTDIR);

    my ($files) = {};
    foreach my $filename (@entries) {
        next    if (($filename eq '.') || ($filename eq '..') || ($filename=~/PreventAD_/i));

        my ($file, $scandir, $newname, $newfile);
        
        if ($filename =~ /(RSN1ep2d64s)(\d\d\d[a-z]\d+)/i) { 
            $files->{'data'}->{'rest_1'}->{'filename'}    = $filename;
            $files->{'data'}->{'rest_1'}->{'scandir'}     = "rest_1";
            $files->{'data'}->{'rest_1'}->{'newname'}     = "rest.nii.gz"; 
        } elsif ($filename =~ /(RSN2ep2d64s)(\d\d\d[a-z]\d+)/i) { 
            $files->{'data'}->{'rest_2'}->{'filename'}    = $filename;
            $files->{'data'}->{'rest_2'}->{'scandir'}     = "rest_2";
            $files->{'data'}->{'rest_2'}->{'newname'}     = "rest.nii.gz"; 
        } elsif ($filename =~ /(oMPRAGEADNIiPAT2s)(\d\d\d)([a-z]\d+)/i) { 
            $files->{'anat'}->{$2}->{'filename'}= $filename;
            $files->{'anat'}->{$2}->{'newname'} = "anat.nii.gz"; 
        } 
    }

    return ($files);

}



sub determineAnatOrder {
    my ($files) = @_;

    my $i = 1;
    foreach my $key_anat (sort keys $files->{'anat'}) {
        my $anat_nb = "anat_" . $i;
        my $filename= $files->{'anat'}{$key_anat}{'filename'};
        my $newname = $files->{'anat'}{$key_anat}{'newname'};

        $files->{'data'}->{$anat_nb}->{'filename'}  = $filename;
        $files->{'data'}->{$anat_nb}->{'scandir'}   = $anat_nb;
        $files->{'data'}->{$anat_nb}->{'newname'}  = $newname;

        $i += 1;
    }
}    


sub getSessionNb {
    my ($visit) = @_;

    my $session;
    if ($visit =~ "NAPBL00") {
        $session = "session_1";
    } elsif ($visit =~ "NAPFU03") { 
        $session = "session_2";
    } elsif ($visit =~ "NAPFU12") {
        $session = "session_3";
    } elsif ($visit =~ "NAPFU24") {
        $session = "session_4";
    }

    return ($session);
}

sub moveNiiFiles {
    my ($files, $session_out_dir) = @_;

    foreach my $key (keys $files->{'data'}) {
        my $tomove  = $session_out_dir . "/" . $files->{'data'}{$key}{'filename'};
        my $scandir = $session_out_dir . "/" . $files->{'data'}{$key}{'scandir'};
        my $newname = $scandir . "/" . $files->{'data'}{$key}{'newname'};

        unless (-e $tomove) {
            print LOG "ERROR: $tomove does not exist. \n";
            next;
        }
        `mkdir $scandir`    unless (-e $scandir);

        if (-e $newname) {
            my $rm_cmd  = "rm $tomove";
            system($rm_cmd);
            print LOG "$newname already exists. Removing $tomove from filesystem. \n";
            next;
        } else {
            my $mv_cmd  = "mv $tomove $newname";
            system($mv_cmd);
        }

        if (-e $newname) {
            print LOG "Sucessfully moved $tomove to $newname.\n";
        } else {
            print LOG "Failed to move $tomove to $newname.\n";
        }
    }
}


sub checkFilesExist {
    my ($session_out_dir) =@_;

    opendir(DIR,$session_out_dir);
    my @entries = readdir(DIR);
    close(DIR);

    my @niilist = grep(/nii\.gz$/,  @entries);
    my @rsnlist = grep(/^rest/,     @entries);

    # Check if nifti files can be found in first resting state directory. if found resting state directories
    my @rsniilist;
    if ($#rsnlist >= 0) {
        opendir(RSNDIR,"$session_out_dir/$rsnlist[0]");
        my @rsnentries  = readdir(RSNDIR);
        close(RSNDIR);

        @rsniilist   = grep(/nii\.gz$/,  @rsnentries);
    }

    # Return 1 if at list one nii file was found in $session_out_dir
    # Return 2 if files were already moved to rest directory within $session_out_dir
    if ($#rsniilist >= 0) {
        return 2;
    } elsif ($#niilist >= 0) {
        return 1;
    } else {
        return undef;
    }
}

sub convert2nii {
    my ($converter, $optionfile, $session_out_dir, $candID, $visit, $dcm_dir) = @_;

    # Convert dcm to nii files
    my $command = $converter                        . 
                    " -b " . $optionfile            . 
                    " -o " . $session_out_dir . " "   . 
                    $dcm_dir;
    print   LOG "\t==> Converting data for candidate $candID, visit $visit.\n";
    system($command);

    # remove files except for anat and resting state files
    my @remove_list = glob "$session_out_dir/AAHScout* $session_out_dir/grefieldmap* $session_out_dir/AXIAL* $session_out_dir/co* $session_out_dir/MPRAGE* $session_out_dir/EN3* $session_out_dir/*pCASL* $session_out_dir/T2SAG* $session_out_dir/*TI900* $session_out_dir/RET*";
    remove_tree(@remove_list, {result => \my $res_list});
    if (@$res_list == 0){
        print   LOG "\t==> No files were deleted.\n";
    }else{
        print   LOG "\t==> Removed the following nifti files @$res_list.\n";
    }
}
