#! /usr/bin/perl

use strict;
use Getopt::Tabular;
use FileHandle;
use File::Basename;
use Date::Parse;
use File::Temp qw/ tempdir /;
use FindBin;

## These are the NeuroDB modules to be used
use NeuroDB::File;
use NeuroDB::MRI;
use NeuroDB::DBI;
use NeuroDB::Notify;

## Set default option values
my $profile     = undef;       # this should never be set unless you are in a stable production environment
my ($megdir, @args);

## Set the help section
my $Usage   =   <<USAGE;
This pipeline will register MEG session and files (.ds) into database.
Important: MEG session must be input in the form PSCID_CandID_Visit_Date.

Usage: $0 [options]

-help for options

USAGE


my @args_table = (
    ["-profile", "string", 1, \$profile, "name of config file in ~/.neurodb"],
    ["-megdir",  "string", 1, \$megdir,  "session meg directory containing the .ds files to register."]
                 );

Getopt::Tabular::SetHelp ($Usage, '');
GetOptions(\@args_table, \@ARGV, \@args) || exit 1;

## Input options error checking
if (!$profile) {
    print "$Usage\n\tERROR: You must specify a profile.\n\n";  
    exit 33;
}
{ package Settings; do "$ENV{HOME}/.neurodb/$profile" }
if ($profile && !defined @Settings::db) {
    print "\n\tERROR: You don't have a configuration file named \"$profile\" in:  $ENV{HOME}/.neurodb/ \n\n"; 
    exit 33;
}

## These settings are in a config file (profile)
my $data_dir    = $Settings::data_dir;
my $prefix      = $Settings::prefix;
my $mail_user   = $Settings::mail_user;
my $ctf_script  = $Settings::ctf_script;

my $User        = `whoami`;

## Create log dir (if !exist) and log file
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $date    = sprintf("%4d-%02d-%02d %02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my $log_dir = $data_dir . "/logs/MEG_pipeline/";
system("mkdir -p -m 755 $log_dir") unless (-e $log_dir);
my $log     = $log_dir . "MEG_insert_" . $date . ".log";
open (LOG, ">>$log");
print LOG "Log file, $date \n";

## Create the temp dir
my $template    = "MegLoad-$hour-$min-XXXXXX"; #for tempdir
my $TmpDir      = tempdir($template, TMPDIR => 1, CLEANUP => 1);

## Establish database connection
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
print LOG "\n==> Successfully connected to database \n";



    # ----- Step 1: Verify PSC information based on megdir name
my ($center_name, $centerID)    = &NeuroDB::MRI::getPSC($megdir, \$dbh);
my $psc                         = $center_name;
if (!$psc) { 
    print LOG "\nERROR: No center found for this meg session \n\n"; 
    exit 77;
}
print LOG  "\n==> Verifying acquisition center\n -> Center Name  : $center_name\n -> CenterID     : $centerID\n";


# ----- Step 2: Determine subject identifiers
if (!defined(&Settings::getMEGSubjectIDs)) {
    print LOG "\nERROR: Profile does not contain getSubjectIDs routine. Upload will exit now.\n\n"; 
    exit 66; 
}
my $megSessionName= basename($megdir);
my $subjectIDsref = &Settings::getMEGSubjectIDs($megSessionName, \$dbh);
if (!$subjectIDsref) {
    print LOG "\nERROR: Could not determine subjectIDsref based on MEG session name\n\n";
    exit 66;
}
print LOG "\n==> Data found for candidate   : $subjectIDsref->{'CandID'} - $subjectIDsref->{'PSCID'} - Visit: $subjectIDsref->{'visitLabel'} - Acquired : $subjectIDsref->{'AcquisitionDate'}";

    
    # ----- Step 3: Get session ID
print LOG "\n\n==> Getting session ID\n";
my ($sessionID, $requiresStaging) = NeuroDB::MRI::getSessionID($subjectIDsref, $subjectIDsref->{'AcquisitionDate'}, \$dbh);
print LOG "    SessionID: $sessionID\n";

    # Make sure MRI Scan Done is set to yes, because now there is data.
if ($sessionID) { 
    my $query = "UPDATE session SET Scan_done='Y' WHERE ID=$sessionID";
    $dbh->do($query);
}


    # ----- Setp 4: Get list of MEG directory (.ds)
my ($meg_files) = &get_megs($megdir); 
if (!$meg_files) {
    print LOG "\nERROR: Could not find MEG files in $megdir\n\n";
    exit 66;
} 
# Count number of meg files to insert into database
my $mcount  = @$meg_files +1;
print LOG "Number of MEG files that will be considered for inserting into the database: $mcount\n";
print "Number of MEG files that will be considered for inserting into the database: $mcount\n";


    # ----- Step 5: Zip and insert MEG files

foreach my $meg (@$meg_files) {
        
    # Extract MEG header information
    my ($hdr)   = &getMEGhdrInfo($megdir, $meg, $TmpDir, $ctf_script); 

    # Tar MEG file in $tmpdir with extracted header information ($hdr, alias *_header.meta)
    my $mtar    = $TmpDir  . "/r2m_" . $$subjectIDsref{'CandID'} . "_" . $$subjectIDsref{'visitLabel'} . "_" . basename($meg) . ".tar.gz";
    my $cmd     = "tar -czf $mtar $megdir/$meg";
    system ($cmd);

    # Create file object
    my $file    = NeuroDB::File->new(\$dbh);

    # Load file from disk
    print LOG "\n==> Loading file from disk $mtar\n";
    $file->loadFileFromDisk($mtar);

    # Compute the md5hash
    print LOG "==> computing md5 hash for MINC body.\n";
    my $md5hash = &NeuroDB::MRI::compute_hash(\$file);
    print LOG " --> md5: $md5hash\n";
    $file->setParameter('md5hash', $md5hash);
    my $unique  = &NeuroDB::MRI::is_unique_hash(\$file);
    if (!$unique) { 
        print LOG " --> WARNING: This file has already been uploaded!"; 
        next; 
    }
     
    # Set some file information
    $file->setFileData('SessionID', $sessionID);
    $file->setFileData('PendingStaging', $requiresStaging);
    $file->setFileData('CoordinateSpace', 'native');
    $file->setFileData('OutputType', 'native');
    $file->setFileData('FileType', 'ds');

    # Grep header information and ls of the meg directory 
    # to insert this information in parameter_file (using setParameter)
    my ($params, $acqDate)  = &getHeaderParam($hdr, $megdir, $meg, $file);

    # Set AcquisitionProtocolID based on MEG scan type
    print LOG "==> verifying acquisition protocol\n";
    my ($acqProtID) = &getAcqProtID("MEG", $dbh);
    $file->setFileData('AcquisitionProtocolID', $acqProtID);
    print LOG "Acq protocol ID: $acqProtID\n";

    # Rename and move file
    my $moved_meg   = &move_meg($mtar, $subjectIDsref, $acqProtID, $data_dir, $prefix, \$file);
    my $file_path   = $moved_meg;
    $file_path      =~ s/$data_dir\///i;
    print LOG "New name: $moved_meg \n";
    $file->setFileData('File', $file_path);

    # Register file into DB
    print LOG "Registering file into DB\n";
    my $fileID  = &NeuroDB::MRI::register_db(\$file);
    print LOG "FileID: $fileID\n";

    # Update mri_acquisition_dates table
    &update_mri_acquisition_dates($sessionID, $acqDate, \$dbh);


}

# Program is finished
exit 0;




##############
## Function ##
##############

=pod
Get list of MEG ds directories to register into DB
Input:  $megdir: folder containing list of .ds MEG directories for this session
Output: \@meg_files: list of MEG .ds directories found for this session
=cut
sub get_megs {
    my ($megdir, $tmpdir) = @_;    

    opendir (MEGDIR, $megdir);
    my @entries = readdir(MEGDIR);
    closedir (MEGDIR);

    my @meg_files;
    foreach my $entry (@entries) {
        next unless ($entry =~ /\.ds$/);  # Only keep .ds directories 
        next if ($entry =~ /AUX\.ds$/);   # Don't want to keep duplicate AUX.ds directories
        push (@meg_files, $entry);
    }

    return (\@meg_files);
}


sub getMEGhdrInfo {
    my ($megdir, $meg, $tmpdir, $ctf_script)   = @_;

    my $hdr = $tmpdir . "/" . substr($meg,0,-3) . "_header.dat";
    my $cmd = "octave -q $ctf_script $megdir/$meg > $hdr";
    system($cmd);

    return undef    unless (-e $hdr);
    return ($hdr);
}


=pod
This function returns the AcquisitionProtocolID of the file to register in DB based on scanType in mri_scan_type.
Inputs: - $scanType: MEG scan type
        - $dbh: database handler
Output: - $acqProtID: acquisitionProtocolID matching MEG scan type
=cut
sub getAcqProtID    {
    my  ($scanType,$dbh)    =   @_;

    my  $acqProtID;
    my  $query  =   "SELECT ID " .
                    "FROM mri_scan_type " .
                    "WHERE Scan_type=?";
    my  $sth    =   $dbh->prepare($query);
    $sth->execute($scanType);
    if($sth->rows > 0) {
        my $row     =   $sth->fetchrow_hashref();
        $acqProtID  =   $row->{'ID'};
    }else{
        return  undef;
    }

    return  ($acqProtID);
}


sub getHeaderParam {
    my ($hdr, $megdir, $meg, $file) = @_;

    my (%params, $date);
    # Insert header information
    open (HEADER, "<$hdr") or die "cannot open file: $!";
    my @hdr_param   = <HEADER>;
    close (HEADER); 
    foreach my $param (@hdr_param) {    
        chomp($param);
        my @split   = split(':', $param);
        my $field   = $split[0];
        my $value   = $split[1];
        $file->setParameter($field, $value);
        $params{$field} = $value;
        if ($field =~ /Date/) {
            my ($ss,$mm,$hh,$day,$month,$year,$zone) = strptime($value);
            $date   = sprintf("%4d%02d%02d",$year+1900,$month+1,$day);
        }
    }

    # Insert .ds directory content
    my @ls  = `ls $megdir/$meg`;
    my $content = join('', @ls);
    $file->setParameter('Content', $content);
    $params{'Content'}    = $content;

    return (\%params, $date);
}


sub update_mri_acquisition_dates {
    my ($sessionID, $acq_date, $dbhr) = @_;
    $dbh = $$dbhr;
    
    # get the registered acquisition date for this session
    my $query = "SELECT s.ID, m.AcquisitionDate from session AS s left outer join mri_acquisition_dates AS m on (s.ID=m.SessionID) WHERE s.ID='$sessionID' and (m.AcquisitionDate > '$acq_date' OR m.AcquisitionDate is null) AND '$acq_date'>0";
    my $sth = $dbh->prepare($query);
    $sth->execute();

    # if we found a session, it needs updating or inserting, so we use replace into.
    if($sth->rows > 0) {
        my $query = "REPLACE INTO mri_acquisition_dates SET AcquisitionDate='$acq_date', SessionID='$sessionID'";
        $dbh->do($query);
    }
}


## move_minc(\$minc, \%minc_ids, $minc_type) -> renames and moves $minc
sub move_meg {
    my ($meg, $subjectIDsref, $acqProtID, $data_dir, $prefix, $fileref) = @_;
    
    my ($new_name, $version);

    # figure out where to put the files
    my $new_dir = $data_dir . "/assembly/" . 
                    $subjectIDsref->{'CandID'} . "/" . 
                    $subjectIDsref->{'visitLabel'} . "/meg/native";
    `mkdir -p -m 755 $new_dir`  unless (-e $new_dir);

    # figure out what to call files
    my $new_pref    = basename($meg); 
    my $ext         = ".tar.gz";
    $new_pref       =~ s/$ext//i;

    my $version     = 1;
    my $extension   = "_" . sprintf("%03d",$version) . $ext;
    my $new_name    = $new_pref . $extension;
    $new_name       =~ s/ //;
    $new_name       =~ s/__+/_/g;

    while (-e "$new_dir/$new_name") {
        $version    = $version + 1;
        $extension  = "_" . sprintf("%03d",$version) . $ext;
        $new_name   = $new_pref . $extension;
        $new_name   =~ s/ //;
        $new_name   =~ s/__+/_/g;
    }

    my $new_path   = $new_dir . "/" . $new_name;
    my $cmd     = "mv $meg $new_path";
    system($cmd);
    print LOG "File $meg \n moved to:\n $new_path\n";

    return ($new_path);
}
