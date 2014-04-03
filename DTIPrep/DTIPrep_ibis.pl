#!/usr/bin/perl -w

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

Will parse DTIPrep outputs directories and call DTIPrep_pipeline.pl on each of them after having determined the source DTI file, protocol file...

Usage: $0 [options]

-help for options

USAGE

# Define the table describing the command-line options
my  @args_table = (
    ["-profile",        "string", 1,  \$profile,        "name of the config file in ~/.neurodb."],
    ["-dir_list",       "string", 1,  \$dir_list,       "DTIPrep subdirectory storing the DTIPrep processed files to be registered"],
    ["-DTIPrepVersion", "string", 1,  \$DTIPrepVersion, "DTIPrep version used for processing."],
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
my  $log_dir     =  "$data_dir/logs/DTIPrep_Preparation";
system("mkdir -p -m 755 $log_dir") unless (-e $log_dir);
my  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
my  $date        =  sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my  $log         =  "$log_dir/DTIPrep_preparation_$date.log";
open(LOG, ">>", $log) or die "Can't write to file '$log' [$!]\n";
print LOG "Log file, $date\n\n";



# Fetch DTIPrep step during which a secondary QCed file will be created (for example: noMC for a file without motion correction). 
# This is set as a config option in the config file.
my  $QCed2_step =  $Settings::QCed2_step;
my  $reg_script =  $Settings::DTIPrepReg_path;

# Establish database connection
my  $dbh    =   &DB::DBI::connect_to_db(@Settings::db);
print LOG "\n==> Successfully connected to database \n";


# Parse through list of directories containing native DTI data (i.e. $data_dir/assembly/DCCID/Visit/mri/native)
open(DIRS,"<$dir_list");
my  @dirs   =   <DIRS>;
close(DIRS);

# Loop through directories
foreach my $dir (@dirs)   {
    chomp ($dir);

    #######################
    ####### Step 1: #######  Grep QCReport in directory
    #######################
    my ($QCReport)  = &DTI::getFilesList($dir, "_QCReport.txt");
    next if (!$QCReport);

    #######################
    ####### Step 2: #######  Grep protocol based on the visit in the directory
    #######################
    my ($protocol, $visit, $candID);
    if ($dir =~  /(\d\d\d\d\d\d)_V(\d\d)$/i)  {       
        $candID     = $1;
        my $visit_nb= $2;
        $visit      = "V" . $visit_nb;
        ($protocol) = &Settings::getDTIPrepProtocol($visit_nb);
    }
    next if ((!$protocol) || (!$candID) || (!$visit));

    #######################
    ####### Step 3: ####### Copy or move data into pipeline folder
    #######################
    my ($QCoutdir) = &moveProcessed($data_dir, $candID, $visit, $protocol, $dir, $DTIPrepVersion);
    next if (!$QCoutdir);

    #######################
    ####### Step 4: ####### Run DTIPrepRegister.pl 
    #######################
&runDTIPrepPipeline($data_dir, $profile, $protocol, $QCReport, $DTIPrepVersion, $dbh);
    ## Need to run it for each DTI acquisition (a.k.a. each $QCReport found in $dir)

}

# Program is finished
exit 0;


###############
## Functions ##
###############

=pod
Fetch native DTI based on QCReport's name.
Inputs: $report: QCReport to use to fetch native DTI
        $dbh: database handler
Output: $nativeDTI: native DTI found in the database corresponding to $report
=cut
sub getNativeDTI {
    my ($report, $data_dir, $dbh) = @_;

    my $query   = "SELECT File " .
                  "FROM files "  . 
                  "WHERE File like ?";
    my $sth     = $dbh->prepare($query);

    my ($nativeDTI, $where);
    if ($report =~ /([a-zA-Z]+_\d\d\d\d\d\d_V\d\d_[a-zA-Z]+_\d\d\d)_QCReport/i) {
        $where  = '%' . $1 . '%';
    } else {
        print LOG "$report does not match regex expresion to use to grep native DWI file.\n";
        return undef;
    }
    $sth->execute($where);
    if ($sth->rows > 0) {
        my $row = $sth->fetchrow_hashref();
        $nativeDTI  = $data_dir . "/" . $row->{'File'};
        $nativeDTI  =~ s/\/\//\//i;
    }

    return ($nativeDTI);
}



=pod
Run DTIPrepRegister.pl on directory $dir.
Inputs: - $profile: prod file in ~/.neurodb
        - $dir: base directory containing DTIPrep outputs to be registered
        - $protocol: protocol used to create DTIPrep outputs to be registered
        - $DTIPrepVersion: DTIPrep version used to create DTIPrep outputs
        - $QCReport_array: list of QCReports found in $dir (one per native DTI file)
        - $dbh: database handler
=cut
sub runDTIPrepPipeline {
    my ($data_dir, $profile, $protocol, $QCReport_array, $DTIPrepVersion, $dbh) = @_;

    # Create list of native files to call DTIPrep_pipeline.pl
    my (@native_files);
    my $native_list = "/tmp/native_list.txt";
    foreach my $report (@$QCReport_array) {
        my ($native) = &getNativeDTI($report, $data_dir, $dbh);
        if ($native) {
            my $native_dir  = dirname($native);
            open (NATLIST, ">>$native_list") or die "Can't write to file '$native_list' [$!]\n";
            print NATLIST "$native_dir\n";
            close (NATLIST);
            push (@native_files, $native);
        } else {
            print LOG "Could not find native DTI corresponding to $report.\n";
            next; 
        }
    }  

    # Call DTIPrep_pipeline.pl if at list one native file was found
    my $command = "DTIPrep_pipeline.pl"              .
                    " -profile "        . $profile        .  
                    " -list "           . $native_list    .
                    " -DTIPrepProtocol ". $protocol       .
                    " -DTIPrepVersion " . $DTIPrepVersion .
                    " -norunDTIPrep "   .
                    " -registerFilesInDB ";
    if (@native_files) {
        print LOG "Running $command\n";
        system($command);
        `rm $native_list`;
    }
}


=pod
Move processed data into $data_dir/pipelines folder according to DTIPrep pipeline's convention.
Inputs: - $data_dir = LORIS MRI data directory (from Settings)
        - $candID   = subject ID
        - $visit    = visit name
        - $protocol = DTIPrep protocol used for processing
        - $dir      = directory containing processed data
        - $DTIPrepVersion   = DTIPrep Version used to process data
Outputs:- undef if data could not be moved to $data_dir/pipeline
        - 1 if all data were moved successfully to $data_dir/pipeline
=cut
sub moveProcessed {
    my ($data_dir, $candID, $visit, $protocol, $dir, $DTIPrepVersion) = @_;

    # Create pipeline directory tree
    my $outdir      = $data_dir . "/pipelines/DTIPrep/" . $DTIPrepVersion;
    my ($QCoutdir)  = &DTI::createOutputFolders($outdir, $candID, $visit, $protocol, 1);
    return undef if (!$QCoutdir);

    # Count number of files present in $dir
    my $count   = `ls $dir | wc -l`;

    # Move processed files into pipeline tree
    opendir (DIR, "$dir") ||  die "cannot open $dir\n";
    my @entries = readdir(DIR);
    closedir (DIR);
    my $copied;
    foreach my $file (@entries) {
        next if (($file eq ".") || ($file eq ".."));
        my $cmd = "cp $dir/$file $QCoutdir";
        system($cmd) unless (-e "$QCoutdir/$file");
        $copied = $copied + 1 if (-e "$QCoutdir/$file");
    }
    # Copy DTIPrep protocol into $QCoutdir
    my $copied_prot = $QCoutdir . "/" . basename($protocol);
    my $cmd2= "cp $protocol $copied_prot\n";
    system($cmd2) unless (-e $copied_prot);
    
    # Check if all files have been moved to $QCoutdir
    if ($copied == $count) {
        print LOG "All files stored in $dir were successfully moved to $QCoutdir";
        return ($QCoutdir);
    } else {
        print LOG "ERROR: all files stored in $dir were not successfully moved to $QCoutdir";
        return undef;
    }
}
