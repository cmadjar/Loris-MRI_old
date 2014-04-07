#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Tabular;
use File::Basename;
use FindBin;
use Date::Parse;
use XML::Simple;
use lib "$FindBin::Bin";

# These are to load the DTI & DBI modules to be used
use DB::DBI;

# Set default option values
my $profile         = undef;
my $Freesurf_subdir = undef;
my @args;

# Set the help section
my  $Usage  =   <<USAGE;

Register a zipped directory of Freesurfer outputs into the database via register_processed_data.pl.

Usage: $0 [options]

-help for options

USAGE

#Define the table describing the command-line options
my @args_table  = (
    ["-profile",              "string", 1,  \$profile,          "name of the config file in ~/.neurodb."],
    ["-Freesurf_subdir",       "string", 1,  \$Freesurf_subdir,   "Freesurfer directory storing the processed files to be registered"]
                  );

Getopt::Tabular::SetHelp ($Usage, '');
GetOptions(\@args_table, \@ARGV, \@args) || exit 1;

# input option error checking
{ package Settings; do "$ENV{HOME}/.neurodb/$profile" }
if  ($profile && !defined @Settings::db) {
    print "\n\tERROR: You don't have a configuration file named '$profile' in:  $ENV{HOME}/.neurodb/ \n\n";
    exit 33;
}
if (!$profile) {
    print "$Usage\n\tERROR: You must specify a profile.\n\n";
    exit 33;
}
if (!$Freesurf_subdir) {
    print "$Usage\n\tERROR: You must specify a Freesurfer subdirectory that contains processed files to be registered in the database.\n\n";
    exit 33;
}

# Needed for log file
my  $data_dir   =  $Settings::data_dir;
my  $log_dir    =  "$data_dir/logs/Freesurf_register";
system("mkdir -p -m 755 $log_dir") unless (-e $log_dir);
my  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
my  $date       =  sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my  $log        =  "$log_dir/Freesurf_register_$date.log";
open(LOG,">>$log");
print LOG "Log file, $date\n\n";

# create the temp dir
my $template    = "TarLoad-$hour-$min-XXXXXX"; # for tempdir
my $TmpDir      = tempdir($template, TMPDIR => 1, CLEANUP => 1 );

# Establish database connection
my  $dbh    =   &DB::DBI::connect_to_db(@Settings::db);
print LOG "\n==> Successfully connected to database \n";

print LOG "\n==> DTI output directory is: $DTIPrep_subdir\n";

# Check that folder to zip is indeed a freesurfer output 
# directory containing all processed subdirectories:
# bem, label, mri, scripts, src, stats, surf, tmp, touch, trash
my ($Freesurf_tar)  = &checkFreesurfDir($Freesurf_subdir, $TmpDir);





exit 0;


################
### Function ###
################

sub checkFreesurfDir {
    my ($Freesurf_subdir, $TmpDir) = @_;

    # Get the list of expected subdir in freesurfer directory
    my $regex   = "^bem|^label|^mri|^scripts|^stats|" .
                  "^surf|^tmp|^touch|^trash";

    ## Read directory $dir and stored its content in @entries 
    opendir  (DIR,"$Freesurf_subdir")   
        ||  die "cannot open $Freesurf_subdir\n";
    my @entries = readdir(DIR);
    closedir (DIR);

    ## Keep only files that match string stored in $match
    my @to_copy = grep(/$regex/i, @entries);
    ## Add directory path to each element (file) of the array 
    @to_copy    = map  {"$Freesurf_subdir/" . $_} @to_copy;
    ## Count number of files to copy
    my $dirs_nb = $#to_copy + 1;

    # if did not find the 10 freesurfer subdirectories, return undef
    unless ($dirs_nb == 10) {
        print LOG "ERROR: could not find all Freesurfer subdirectories\n";
        return undef;
    }

    # Copy all freesurfer subdirectories to /tmp
    system("mkdir -p -m 755 $TmpDir/freesurfer") unless (-e "$TmpDir/freesurfer");
    my $count;
    foreach my $subdir (@to_copy) {
        my $basename    = basename($subdir);
        my $cmd         = "cp $subdir $TmpDir/freesurfer/";
        system ($cmd);
        $count += 1     if (-e "$TmpDir/freesurfer/$subdir");
    }

    # if the 10 freesurfer subdirectories were not copied into /tmp, return undef
    unless ($count == 10) {
        print LOG "ERROR: not all Freesurfer directories were copied in /tmp. \n";
        return undef;
    }

    # tar freesurfer directory stored in $TmpDir
    my $tar = "$TmpDir/freesurfer.tar";
    my $cmd = "tar -cf $tar $Tmp/freesurfer";
    system ($cmd);

    if (-e $tar) {
        return $tar;
    } else {
        print LOG "ERROR: tar of the freesurfer outputs could not be created.\n"; 
        return undef;
    }

}
