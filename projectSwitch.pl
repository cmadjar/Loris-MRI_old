#! /usr/bin/perl

=pod

This script will update subproject and visit label when participant switches
to a clinical trial after having performed an EN and BL under the cohort labeling.

=cut

use strict;
use Carp;
use Getopt::Tabular;
use FileHandle;
use File::Basename;
use File::Temp qw/ tempdir /;
use FindBin;
use Cwd qw/ abs_path /;

# These are the NeuroDB and DICOM modules to be used
use lib "$FindBin::Bin";
use NeuroDB::File;
use NeuroDB::MRI;
use NeuroDB::DBI;
use NeuroDB::Notify;


my $profile =   undef;
my $oldPatientName;
my @args;

my $Usage   =   <<USAGE;

This script will update visit label and subproject ID of sessions when a participant is swithing from the cohort to a clinical trial after it EN or BL scan.

Usage: perl projectSwitch.pl [options]

-help for options

USAGE

my @args_table  =   (
    ["-profile", "string", 1, \$profile, "name of config file in ~/.neurodb."],
    ["-oldPatientName","string",1,\$oldPatientName, "Old patient name given by the scanner, i.e. PSCID_DCCID_VisitLabel. Example: MTL0001_123456_PREEN00."]
);

Getopt::Tabular::SetHelp ($Usage, '');
GetOptions(\@args_table, \@ARGV, \@args) || exit 1;

# input option error checking
{ package Settings; do "$ENV{HOME}/.neurodb/$profile" }
if ($profile && !defined @Settings::db) {
        print "\n\tERROR: You don't have a configuration file named '$profile' in:  $ENV{HOME}/.neurodb/ \n\n"; exit 33;
}
if(!$profile) { print "$Usage\n\tERROR: You must specify a profile.\n\n";  exit 33;}

# make sure the old PatientName matches the requirements PSCID_DCCID_VisitLabel
unless((defined($oldPatientName))&&($oldPatientName =~ /^[A-Z][A-Z][A-Z]\d\d\d\d_\d\d\d\d\d\d_[A-Z][A-Z][A-Z][A-Z][A-Z]\d\d$/)){ print "$Usage\n\tERROR: you need to specify the old PatientName using -oldPatientName PSCID_DCCID_VisitLabel.\n\n";exit 33;}

# needed for log file
my $data_dir=   $Settings::data_dir;
my $log_dir =   "$data_dir/logs/ProjectSwitch";
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
my $date    =   sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my $log     =   "$log_dir/ProjectSwitch$date.log";
open(LOG,">>$log");
print LOG "Log file, $date\n\n";

# establish database connection
my $dbh     =   &NeuroDB::DBI::connect_to_db(@Settings::db);
print "\n==> Successfully connected to database \n";

# Get the PSCID, CandID, old visit label and old subprojectID from the PatientName
my ($pscID, $candID,$oldLabel,$oldSubprojectID);
if($oldPatientName =~ m/^([A-Z][A-Z][A-Z]\d\d\d\d)_(\d\d\d\d\d\d)_([A-Z][A-Z][A-Z][A-Z][A-Z]\d\d)$/i){
        $pscID=$1;
        $candID=$2;
        $oldLabel=$3;
        if      ($oldLabel  =~  m/^PRE/i)   { $oldSubprojectID=1;}
        elsif   ($oldLabel  =~  m/^NAP/i)   { $oldSubprojectID=2;}
        elsif   ($oldLabel  =~  m/^PRO/i)   { $oldSubprojectID=3;}
        elsif   ($oldLabel  =~  m/^INS/i)   { $oldSubprojectID=4;}
}
print "PSCID: $pscID\nCandID: $candID\nOld label: $oldLabel\nOld subprojectID: $oldSubprojectID\n";

# Get the SessionID from the tarchive table.
my ($sessionID,$ArchiveLocation,$DateAcquired)  =   getArchiveInfos($oldPatientName,$data_dir,$dbh);
print "SessionID: $sessionID\n";
print "ArchiveLocation is: $ArchiveLocation\n";
print "DateAcquired is: $DateAcquired\n";

# Get the new visit label from the session table.
my $newVisitLabel   =   getNewVisitLabel($sessionID,$dbh);
print "New visit label: $newVisitLabel\n";

# Produce the new PatientName based on the new visit label and get the new subprojectID
my $newPatientName  =   $pscID."_".$candID."_".$newVisitLabel;
print "New PatientName: $newPatientName\n";
my $newSubprojectID;
if      ($newVisitLabel =~  m/^PRE/i)   { $newSubprojectID=1;}
elsif   ($newVisitLabel =~  m/^NAP/i)   { $newSubprojectID=2;}
elsif   ($newVisitLabel =~  m/^PRO/i)   { $newSubprojectID=3;}
elsif   ($newVisitLabel =~  m/^INS/i)   { $newSubprojectID=4;}
print "New SubprojectID: $newSubprojectID\n";

# create the temp dir
my $tempdir =   tempdir( CLEANUP => 0 );

# Check that SeriesUID and EchoTime are populated in files_qcstatus and feedback_mri_comments tables for the session
my  ($QCsafe)   =   check_filesQC_filesComments($sessionID,$dbh,"files_qcstatus");   
if  ($QCsafe)   { print "\n STOP: SeriesUID and EchoTime are not populated in files_qcstatus for all files in session $sessionID.\n"; exit 33;}

my  ($feedback_safe)    =   check_filesQC_filesComments($sessionID,$dbh,"feedback_mri_comments");   
if  ($feedback_safe)    { print "\n STOP: SeriesUID and EchoTime are not populated in feedback_mri_comments for all files in session $sessionID.\n"; exit 33;}

# Run archiveUpdateDeleteMRI on the $ArchiveLocation
my $toremove    =   createTempList($tempdir,$ArchiveLocation);
my  $command    =   "perl archiveUpdateDeleteMRI -profile $profile -archive -update -delete -list $toremove"; 
print $command."\n";  
#system($command);

# Delete tarchive from the tarchive table.
#my  ($rows_deleted) =   deleteTarchive($ArchiveLocation,$sessionID,$dbh); 
#if  ($rows_deleted)     { print "Deleted $rows_deleted in tarchive table for session $sessionID, archive $ArchiveLocation\n"; }

# Extract the tarchive in tempdir folder
my  ($dcmdir)       =   extract_tarchive($ArchiveLocation,$tempdir);
my  ($new_dcmdir)   =   update_dicom_headers($dcmdir,$tempdir,$oldPatientName,$newPatientName);

# Reload tarchive.
print "Rebuilding tarchive...\n";
my  $DICOMTAR       =   $FindBin::Bin."/dicom-archive/dicomTar.pl";
my  $tarchiveDir    =   $Settings::tarchiveLibraryDir;
my  $cmd            =   "$DICOMTAR $tempdir/$new_dcmdir $tarchiveDir -database -profile $profile -clobber";
print $cmd."\n";
system($cmd);

# Run batch_upload_tarchive.
print "Running batch_uploads_tarchive... \n";
my  ($newSessionID,$newArchiveLocation,$newDateAcquired)  =   getArchiveInfos($newPatientName,$data_dir,$dbh);
my  $toreload   =   createTempList($tempdir,$newArchiveLocation);
my  $UPLOAD_TAR =   $FindBin::Bin."/batch_uploads_tarchive";  
my  $cmd        =   "$UPLOAD_TAR < $toreload";
system($cmd);

#############
# Functions #
#############

=pod
Get the sessionID from the tarchive table based on the old PatientName.
=cut
sub getArchiveInfos {
    my ($oldPatientName,$data_dir,$dbh)   =   @_;
    my $sessionID;

    my $query   =   "SELECT SessionID,ArchiveLocation,DateAcquired FROM tarchive where PatientName=?";
    my $sth     =   $dbh->prepare($query);
    $sth->execute($oldPatientName);
    if  ($sth->rows > 0)    {
        my $row         =   $sth->fetchrow_hashref();
        $sessionID      =   $row->{'SessionID'};
        $ArchiveLocation=   $row->{'ArchiveLocation'};
        $DateAcquired   =   $row->{'DateAcquired'};
    }else{
        print "\n ERROR: could not find a tarchive registered in the database with PatientName $oldPatientName.\n"; exit 33;
    }
    
    # Get the ArchiveLocation before batch_upload_tarchive was run (in tarchive directory)
    my  $ArchivePath    =   dirname($ArchiveLocation);
    if  ($ArchiveLocation=~m/(\d+)\/(DCM_\d\d\d\d-\d\d-\d\d)_($oldPatientName)_(\d+)_(\d+)_(\d).tar$/i) {
        $ArchiveLocation    =   $data_dir."/tarchive/".$2."_".$oldPatientName."_".$4."_".$5.".tar";
    }
    unless  (-e $ArchiveLocation)   { print "\n ERROR: $ArchiveLocation does not exists.\n"; exit 33;}

    return  ($sessionID,$ArchiveLocation,$DateAcquired);
}

=pod
Get the new visit label from the session table using SessionID.
=cut
sub getNewVisitLabel{
    my ($sessionID,$dbh)    =   @_;
    my $newVisitLabel;

    my $query   =   "SELECT Visit_label from session where ID=?";
    my $sth     =   $dbh->prepare($query);
    $sth->execute($sessionID);
    if  ($sth->rows > 0)    { my @row = $sth->fetchrow_array(); $newVisitLabel=$row[0];}

    return  ($newVisitLabel);
}

=pod
Make sure the SeriesUID and EchoTime fields are not null in files_qcstatus and feedback_mri_comments before deleting files in the files, parameter_file and mri_acquisition_date table for the session.
=cut
sub check_filesQC_filesComments{
    my ($sessionID,$dbh,$table)    =   @_;

    my ($query);
    if      ($table eq "files_qcstatus")    {
        $query   =   "SELECT fq.FileID FROM files AS f JOIN files_qcstatus AS fq ON fq.FileID=f.FileID WHERE (fq.SeriesUID IS NULL OR fq.EchoTime IS NULL) AND f.SessionID=?";
    }elsif  ($table eq "feedback_mri_comments")  {
        $query   =   "SELECT fmc.FileID FROM files AS f JOIN feedback_mri_comments AS fmc ON fmc.FileID=f.FileID WHERE (fmc.SeriesUID IS NULL OR fmc.EchoTime IS NULL) AND fmc.SessionID IS NULL AND f.SessionID=?";
    }    

    my $sth =   $dbh->prepare($query);
    $sth->execute($sessionID);

    if  ($sth->rows > 0)    {
        my @FileIDs =   $sth->fetchrow_array();
        return @FileIDs ;
    }

    return  undef;
}

=pod
Delete tarchive entry with old Patient Name in the tarchive table.
=cut
sub deleteTarchive  {
    my  ($ArchiveLocation,$sessionID,$dbh)  =   @_; 

    my $query       =   "DELETE FROM tarchive WHERE ArchiveLocation=? AND SessionID=?";
    my @bind_values =   ($ArchiveLocation,$sessionID);   
    my $rows_deleted =   $dbh->do($query,undef,@bind_values) or die $dbh->errstr; 
    
    return  ($rows_deleted); 
}
=pod
Extract the tarchive in temp directory.
=cut
sub extract_tarchive {
     my ($tarchive, $tempdir)   =   @_;

     print "Extracting tarchive\n";
     `cd $tempdir ; tar -xf $tarchive`;
     opendir    (TMPDIR, $tempdir);
     my @tars   =   grep { /\.tar\.gz$/ && -f "$tempdir/$_" }   readdir(TMPDIR);
     closedir   TMPDIR;

     if (scalar(@tars) != 1)    {
          print "Error: Could not find inner tar in $tarchive!\n";

          print @tars . "\n";
          exit 33;
     }

     my $dcmtar     =   $tars[0];
     my $dcmdir     =   $dcmtar;
     $dcmdir        =~  s/\.tar\.gz$//;

     `cd $tempdir ; tar -xzf $dcmtar`;

     return $dcmdir;
}

=pod
=cut
sub createTempList {
    my  ($tempdir,$text)    =   @_;

    my  $tmpList =   $tempdir."/tarchive_list.txt";
    # Create a file containing the list of Archive to use to run archiveUpdateDeleteMRI.
    unless  (open FILE, '>'.$tmpList)    { print "\n ERROR: Unable to create $tmpList\n"; exit 33;}
    print FILE "$text\n";
    close FILE;
    
    return  ($tmpList);
}

=pod
Update dicom file header.
=cut
sub update_dicom_headers {
    my  ($dcmdir,$tempdir,$oldPatientName,$newPatientName)   =   @_;    
    my  $dir    =   $tempdir."/".$dcmdir; 
    opendir (DIR, $dir) or die $!;
    while (my $file = readdir(DIR)){
        next if ($file =~ m/^\./);
        next if ($file =~ m/.bak/);
        my $f = $dir."/".$file;
        print "Updating header of file $f ...\n";
        my $command =   "dcmodify -ma PatientName=$newPatientName $f";
        system($command);
    }
    closedir(DIR);
    
    print "Deleting .bak files.\n";
    `rm $dir/*.bak`;

    my $new_dcmdir;
    if($dcmdir =~ m/($oldPatientName)_(\d+)_(\d+)/i){
        $new_dcmdir =   $newPatientName."_".$2."_".$3;
        print $new_dcmdir."\n";
    } else { print "$dcmdir does not match oldPatientName_1111_111.\n"; exit 33; }
    my $newdir  =   $tempdir."/".$new_dcmdir;
    print "Renaming $tempdir/$dcmdir to $tempdir/$new_dcmdir.\n";
    rename($dir,$newdir);

    return ($new_dcmdir);
}

