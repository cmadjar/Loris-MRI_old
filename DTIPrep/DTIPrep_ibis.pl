#! /usr/bin/perl

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
use DTI::DTI;

# Set default option values
my $profile         = undef;
my $dir_list        = undef;
my $DTIPrepVersion  = undef;
my @args;

# Set the help section
my  $Usage  =   <<USAGE;

Will parse DTIPrep outputs directories and call DTIPrepRegister.pl on each of them after have determined source DTI file, protocol file...

Usage: $0 [options]

-help for options

USAGE

# Define the table describing the command-line options
my  @args_table = (
    ["-profile",        "string", 1,  \$profile,          "name of the config file in ~/.neurodb."],
    ["-dir_list",       "string", 1,  \$DTIPrep_subdir,   "DTIPrep subdirectory storing the DTIPrep processed files to be registered"],
    ["-DTIPrepVersion", "string", 1,  \$DTIPrepVersion,   "DTIPrep version used for processing."],
);

Getopt::Tabular::SetHelp ($Usage, '');
GetOptions(\@args_table, \@ARGV, \@args) || exit 1;

# input option error checking
if (!$profile) {
    print "$Usage\n\tERROR: You must specify a profile.\n\n";
    exit 33;
}
{ package Settings; do "$ENV{HOME}/.neurodb/$profile" }
if  ($profile && !defined @Settings::db) {
    print "\n\tERROR: You don't have a configuration file named '$profile' in:  $ENV{HOME}/.neurodb/ \n\n";
    exit 33;
}
if (!$dir_list) {
    print "$Usage\n\tERROR: You must specify a list of DTIPrep directories with processed files to be registered in the database.\n\n";
    exit 33;
}
if (!$DTIPrepVersion) {
    print "$Usage\n\tERROR: You must specify the version of DTIPrep used to process the DTI files.\n\n";
    exit 33;
}

# Needed for log file
my  $data_dir    =  $Settings::data_dir;
my  $log_dir     =  "$data_dir/logs/DTIPrep_registrationPreparation";
my  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
my  $date        =  sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my  $log         =  "$log_dir/DTIPrep_preparation_$date.log";
open(LOG,">>$log");
print LOG "Log file, $date\n\n";



# Fetch DTIPrep step during which a secondary QCed file will be created (for example: noMC for a file without motion correction). 
# This is set as a config option in the config file.
my  $QCed2_step =  $Settings::QCed2_step;

# Establish database connection
my  $dbh    =   &DB::DBI::connect_to_db(@Settings::db);
print LOG "\n==> Successfully connected to database \n";


# Parse through list of directories containing native DTI data (i.e. $data_dir/assembly/DCCID/Visit/mri/native)
open(DIRS,"<$list");
my  @dirs   =   <DIRS>;
close(DIRS);

# Loop through directories
foreach my $dir (@dirs)   {
    chomp ($dir);

    #######################
    ####### Step 1: #######  Grep QCReport in directory
    #######################
    my ($QCReport)  = &DTI::getFilesList($dir, "_QCReprot.txt");
    next if (!$QCReport);

    #######################
    ####### Step 2: #######  Grep protocol based on the visit in the directory
    #######################
    my $protocol;
    if ($dir =~  /^[a-z]_\d\d\d\d\d\d_V(\d\d)_/i)  {       
        my  $visit_nb   = $1;
        ($protocol)     = $Settings::getDTIPrepProtocol($visit_nb);
    }
    next if (!$protocol);

    #######################
    ####### Step 3: #######  Get native DTI file based on QCReports
    #######################
    ## Need to think in case there are multiple DTI acquisition
    
    #######################
    ####### Step 4: #######  Run DTIPrepRegister
    #######################
    ## Need to run it for each DTI acquisition
    


# $register_cmd    = "perl DTIPrepRegister.pl -profile $profile -DTIPrep_subdir $dir -DTIPrepProtocol \"$protocol\" -DTI_file $dti_file -DTIPrepVersion \"$DTIPrepVersion\"";


exit 0;


###############
## Functions ##
###############

# Fetch protocol based on directory name.
sub  get_DTI_Site_CandID_Visit {
    my ($dir) =   @_;

    if  ($dir =~  /^[a-z]_\d\d\d\d\d\d_V(\d\d)_/i)  { 
        my  $visit  =   $1;
        return  ($site, $subjID, $visit);
    }else{
        return  undef;
    }

}

