#!/usr/bin/perl -w

use strict;
use warnings;
use Getopt::Tabular;
use File::Basename;
use FindBin;
use Date::Parse;
use File::Temp qw/ tempdir /;
use lib "$FindBin::Bin";

# These are to load the DTI & DBI modules to be used
use NeuroDB::DBI;

my $profile	= undef;
my $fs_dir  = undef;
my @args;

# Set the help section
my $Usage   = <<USAGE;

Register a tar file of Freesurfer output directory into the database via register_processed_data.pl.

Usage: $0 [options]

-help for options

USAGE

# Define the tabl describing the command-line options
my @args_table  = (
    ["-profile",        "string",   1,  \$profile,  "name of the config file in ~/.neurodb."],
    ["-freesurf_dir",   "string",   1,  \$fs_dir,   "freesurfer directory containing freesurfer outputs to be registered into the database. Should be named basename(t1)_freesurfer (i.e. r2m_476534_V00_t1_001_freesurfer)."]
);

Getopt::Tabular::SetHelp ($Usage, '');
GetOptions(\@args_table, \@ARGV, \@args) || exit 1;

# Input option error checking
{ package Settings; do "$ENV{HOME}/.neurodb/$profile" }
if  ($profile && !defined @Settings::db) {
        print "\n\tERROR: You don't have a configuration file named '$profile' in:  $ENV{HOME}/.neurodb/ \n\n"; 
            exit 33;
}
if (!$profile) {
        print "$Usage\n\tERROR: You must specify a profile.\n\n";  
            exit 33;
}
if (!$fs_dir) {
        print "$Usage\n\tERROR: You must specify a freesurfer directory with processed files to be registered in the database.\n\n";
            exit 33;
}

# Needed for log file
my  $data_dir    =  $Settings::data_dir;
my  $log_dir     =  "$data_dir/logs/Freesurfer_register";
my  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
my  $date        =  sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my  $log         =  "$log_dir/Freesurfer_register_$date.log";
open(LOG,">>$log");
print LOG "Log file, $date\n\n";

# For tar file of freesurfer
my $template    = "TarFreesurf-$hour-$min-XXXXXX"; # for tempdir
# create the temp dir
my $TmpDir      = tempdir($template, TMPDIR => 1, CLEANUP => 1 );
# create logdir(if !exists) and logfile
my @temp        = split(/\//, $TmpDir); 
my $templog     = $temp[$#temp];
my $LogDir      = "$data_dir/logs"; if (!-d $LogDir) { mkdir($LogDir, 0700); }
my $logfile     = "$LogDir/$templog.log";
open LOG, ">$logfile";
LOG->autoflush(1);
&logHeader();

# Establish database connection
my  $dbh    =   &NeuroDB::DBI::connect_to_db(@Settings::db);
print LOG "\n==> Successfully connected to database \n";

print LOG "\n==> Freesurfer output directory is: $fs_dir\n";

    ##############
    ### Step 1 ###
    ##############

# Grep source T1 FileID based on Freesurfer directory name
my $srcFileID   = &getSourceFileID($fs_dir);
if (!$srcFileID) {
    print LOG "\nERROR:\n\tCould not determine source T1 used to produce $fs_dir.\n";
    exit;
}

    ##############
    ### Step 2 ###
    ##############

# Fetch processing date and tool information using fs_dir/script/recon-all.done log file.
my $logFile                 = $fs_dir . "/scripts/recon-all.done";
my ($procDate, $procTool)   = &getProcessInfo($logFile);
if ((!$procDate) || (!$procTool)) {
    print LOG "\nERROR:\n\tCould not determine processing date or processing tool used to produce $fs_dir.\n";
    exit;
}

    ##############
    ### Step 3 ###
    ##############

# Tar the whole thing up
my $fs_tar  = $TmpDir . "/" . basename($fs_dir) . ".tar.gz";
my $tar_cmd = "tar -czvf $fs_tar $logFile";
system($tar_cmd);
unless (-e $fs_tar) {
    print LOG "\nERROR:\n\tTar file $fs_tar of $fs_dir was not created.\n";
    exit;
}

    ##############
    ### Step 4 ###
    ##############

# Register file into database
my ($registered)    = &registerFreesurf($fs_tar, $procDate, $procTool, $data_dir);


exit 0;

#####################
####  Functions  ####
#####################

=pod
Get file ID of the source t1 file used to obtain freesurfer output directory
Input: - $fs_dir    = freesurfer output directory named basename(t1)_freesurfer
Output:- $srcFileID = FileID of the t1 source file grepped from the files table 
=cut
sub getSourceFileID {
    my ($fs_dir)    = @_;

    my $t1_basename = basename($fs_dir);
    $t1_basename    =~ s/_freesurfer//i;

    my $query       = "SELECT FileID " .
                        "FROM files "  .
                        "WHERE File LIKE ? ";
    my $sth         = $dbh->prepare($query);
    $sth->execute("%$t1_basename%");
    
    my $srcFileID;
    if ($sth->rows > 0) {
        my $row     = $sth->fetchrow_hashref();
        $srcFileID  = $row->{'FileID'};
    }

    return ($srcFileID);
}

=pod
Grep processing information such as processing date and tool from freesurfer log file.
Input:   - $logFile   = freesurfer log file found in freesurfer directory (in scripts/recon-all.done)
Outputs: - $procDate  = processing date
         - $procTool  = processing tool including version used to obtain freesurfer output directory
=cut
sub getProcessInfo {
    my ($logFile)   = @_;

    # Read the log file 
    open (FILE, "<" , $logFile) or die $!;
    my @lines   = <FILE>;
    close (FILE);

    # Grep line starting with start_time and version
    my ($date, $procTool);
    foreach my $line (@lines) {
        next unless (($line =~ /^START_TIME/i) || ($line =~ /\$Id:/i));
        $date       = $line     if ($line =~ /^START_TIME/i);
        $procTool   = $line     if ($line =~ /\$Id:/i);
    }
    $date       =~ s/START_TIME//i;
    my ($ss,$mm,$hh,$day,$month,$year,$zone) = strptime($date);
    my $proDate = sprintf("%4d%02d%02d", $year+1900, $month+1, $day);

    return ($proDate, $procTool);
}

=pod
Header to be printed in the LOG file.
=cut
sub logHeader () {
    print LOG "
----------------------------------------------------------------------------------------------------------
                              AUTOMATED DICOM DATA UPLOAD
----------------------------------------------------------------------------------------------------------
*** Date and time of upload    : $date
*** Location of source data    : $fs_dir
*** tmp dir location           : $TmpDir
";
}


=pod
=cut
sub registerFreesurf {
    my ($fs_tar, $procDate, $procTool, $data_dir) = @_;
    
    my $md5check        = `md5sum $fs_tar`;
    my ($md5sum, $file) = split(' ',$md5check);
    my ($fsTarID)       = &fetchFsTarID($md5sum);

    return ($fsTarID)   if ($fsTarID);

    # Determine source file name and source file ID
    my ($src_name)              = basename($fs_tar, '_freesurfer.tar.gz');
    my ($src_fileID, $reg_file) = &getFileID($fs_tar, $src_name);

    # Set other information needed for the insertion 
    my $src_pipeline    = "freesurfer";
    my $coordinateSpace = "stereotaxic";
    my $outputType      = "processed";
    my $scanType        = "freesurfer";
    my $inputs          = $reg_file;  # only one input, being the t1

    # Register freesurfer tar file
    ($fsTarID)  = &registerFile($fs_tar, 
                                $src_fileID,
                                $src_pipeline, 
                                $procTool,
                                $procDate, 
                                $coordinateSpace, 
                                $scanType, 
                                $outputType,
                                $inputs
                               );

    return ($fsTarID);
}


=pod
=cut
sub fetchFsTarID {
    my ($md5sum) = @_;

    my $query   = "SELECT f.FileID " .
                    "FROM files f " .
                    "JOIN parameter_file pf " .
                      "ON pf.FileID=f.FileID " .
                    "JOIN parameter_type pt " .
                      "ON pt.ParameterTypeID=pf.ParameterTypeID " .
                    "WHERE pt.Name='md5hash' " .
                      "AND pf.Value=?";
    my $sth     = $dbh->prepare($query);
    $sth->execute($md5sum);

    my $fsTarID;
    if ($sth->rows > 0) {
        my $row     = $sth->fetchrow_hashref();
        $fsTarID    = $row->{'FileID'};
    }

    return ($fsTarID);
}




=pod
Fetches the source FileID from the database based on the src_name file identified by getFileName.
Inputs: - $file     = output filename 
        - $src_name = source filename (file that has been used to obtain $file)
Outputs: - $fileID  = source File ID (file ID of the source file that has been used to obtain $file)
=cut
sub getFileID {
    my  ($file, $src_name) = @_;

    my ($fileID, $registered_file);

    # fetch the FileID of the raw dataset
    my $query   =   "SELECT FileID, File " .
                    "FROM files " . 
                    "WHERE File like ?";
    
    my $like    =   "%$src_name%";    
    my $sth     =   $dbh->prepare($query); 
    $sth->execute($like);
    
    if  ($sth->rows > 0)    {
        my $row         =   $sth->fetchrow_hashref();
        $fileID         =   $row->{'FileID'};
        $registered_file=   $row->{'File'};
    }else   {
        print LOG "WARNING: No fileID matches the dataset $src_name used to produce $file.\n\n\n";
    }
    
    return  ($fileID, $registered_file);
}




=pod
Register file into the database via register_processed_data.pl with all options.
Inputs:  - $file            = file to be registered in the database
         - $src_fileID      = FileID of the source file used to obtain the file to be registered
         - $src_pipeline    = Pipeline used to obtain the file (DTIPrepPipeline)
         - $src_tool        = Name and version of the tool used to obtain the file (DTIPrep or mincdiffusion)
         - $pipelineDate    = file's creation date (= pipeline date)
         - $coordinateSpace = file's coordinate space (= native, T1 ...)
         - $scanType        = file's scan type (= QCedDTI, FAqc, MDqc, RGBqc...)
         - $outputType      = file's output type (.xml, .txt, .mnc...)
         - $inputs          = files that were used to create the file to be registered (intermediary files)
Outputs: - $registeredFile  = file that has been registered in the database
=cut
sub registerFile {
    my ($file, $src_fileID, $src_pipeline, $procTool, $procDate, $coordinateSpace, $scanType, $outputType, $inputs) = @_;

    # Print LOG information about the file to be registered
    print LOG "\n\t- sourceFileID is: $src_fileID\n";
    print LOG "\t- src_pipeline is: $src_pipeline\n";
    print LOG "\t- tool is: $procTool\n";
    print LOG "\t- pipelineDate is: $procDate\n";
    print LOG "\t- coordinateSpace is: $coordinateSpace\n";
    print LOG "\t- scanType is: $scanType\n";
    print LOG "\t- outputType is: $outputType\n";
    print LOG "\t- inputFileIDs is: $inputs\n";

    # Register the file into the database using command $cmd
    my $cmd = "register_processed_data.pl " .
                    "-profile $profile " .
                    "-file $file " .
                    "-sourceFileID $src_fileID " .
                    "-sourcePipeline $src_pipeline " .
                    "-tool \"$procTool\" " .
                    "-pipelineDate $procDate " .
                    "-coordinateSpace $coordinateSpace " .
                    "-scanType $scanType " .
                    "-outputType $outputType  " .
                    "-inputFileIDs \"$inputs\" ";
    system($cmd);
    print LOG "\n==> Command sent:\n$cmd\n";

    my  ($registeredFile) = &fetchRegisteredFile($src_fileID, $src_pipeline, $procDate, $coordinateSpace, $scanType, $outputType);

    if (!$registeredFile) {
        print LOG "> WARNING: No fileID found for SourceFileID=$src_fileID, SourcePipeline=$src_pipeline, PipelineDate=$procDate, CoordinateSpace=$coordinateSpace, ScanType=$scanType and OutputType=$outputType.\n\n\n";
    }    

    return ($registeredFile);
}



=pod
Fetch the registered file from the database to link it to the minc files.
Inputs:  - $src_fileID      = FileID of the native file used to register the processed file
         - $src_pipeline    = Pipeline name used to register the processed file
         - $pipelineDate    = Pipeline data used to register the processed file
         - $coordinateSpace = coordinate space used to register the processed file
         - $scanType        = scan type used to register the processed file
         - $outputType      = output type used to register the processed file
Outputs: - $registeredFile  = path to the registered processed file
=cut
sub fetchRegisteredFile {
    my ($src_fileID, $src_pipeline, $pipelineDate, $coordinateSpace, $scanType, $outputType) = @_;

    my $registeredFile;

    # fetch the FileID of the raw dataset
    my $query   =   "SELECT f.File "          .
                    "FROM files f "             .
                    "JOIN mri_scan_type mst "   .
                        "ON mst.ID=f.AcquisitionProtocolID ".
                    "WHERE f.SourceFileID=? "   .
                        "AND f.SourcePipeline=? "   .
                        "AND f.PipelineDate=? "     .
                        "AND f.CoordinateSpace=? "  .
                        "AND mst.Scan_type=? "      .
                        "AND OutputType=?";

    my $sth     =   $dbh->prepare($query);
    $sth->execute($src_fileID, $src_pipeline, $pipelineDate, $coordinateSpace, $scanType, $outputType);

    if  ($sth->rows > 0)    {
        my $row =   $sth->fetchrow_hashref();
        $registeredFile =   $row->{'File'};
    }

    return  ($registeredFile);

}
