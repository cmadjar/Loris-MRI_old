#! /usr/bin/perl

use strict;
use warnings;
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
my $megdir      = undef;
my $pic_fold    = undef;
my (@args);

## Set the help section
my $Usage   =   <<USAGE;
This pipeline will register MEG session and files (.ds) into database.
Important: MEG session must be input in the form PSCID_CandID_Visit_Date.

Usage: $0 [options]

-help for options

USAGE


my @args_table = (
    ["-profile", "string", 1, \$profile, "name of config file in ~/.neurodb"],
    ["-megdir",  "string", 1, \$megdir,  "session meg directory containing the .ds files to register."],
    ["-picdir",  "string", 1, \$pic_fold,"folder containing the png images for each MEG scan."]
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
if (!$megdir) {
    print "\n\tERROR: You need to specify a session directory containing the .ds MEG files to register.\n\n";
    exit 33;
}
if (!$pic_fold) {
    print "\n\tERROR: You need to specify a directory containing the .png images to associate with the MEG files to be registered.\n\n";
    exit 33;
}

# Remove last / from the directory if present
$megdir  =~ s/\/$//i;    
$pic_fold=~ s/\/$//i;

## These settings are in a config file (profile)
my $data_dir    = $Settings::data_dir;
my $pic_dir     = $data_dir.'/pic';
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
    chdir($megdir);
    my $mtar    = $TmpDir  . "/r2m_" . $$subjectIDsref{'CandID'} . "_" . $$subjectIDsref{'visitLabel'} . "_" . basename($meg) . ".tgz";
    my $cmd     = "tar -czf $mtar $meg";
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

    # Grep and create the pic associated to the MEG file to be registered
    my ($pic)   = &create_pic($meg, $pic_fold);

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

    # Create MEG pics (use $meg_basename to find which pic to associate with registered MEG file)
    &NeuroDB::MRI::register_pic(\$file, $data_dir, $pic_dir, $pic, $dbh);

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

=pod
Function that runs octave script on the MEG file to output MEG header
information into a .dat file.
Inputs: - $megdir: MEG directory
        - $meg: MEG file
        - $tmpdir: tmp directory in which the .dat file will be created
        - $ctf_script: octave script that parses the MEG header.
Outputs:- $hdr: .dat file containing all MEG header information
=cut
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

=pod
Reads MEG header file to gather information regarding the MEG acquisition 
that will be inserted into the database.
Inputs: - $hdr: file containing the header information
        - $megdir: MEG directory
        - $meg: MEG file
        - $file: hash containing all information about the MEG file to be inserted into the database.
Outputs:-\%params: hash containing MEG parameters
        - $date: acquisition date of the MEG file
=cut
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
        if ($field =~ /Date/) {
            my ($ss,$mm,$hh,$day,$month,$year,$zone) = strptime($value);
            $date   = sprintf("%4d%02d%02d",$year+1900,$month+1,$day);
            $file->setParameter('acquisition_date', $date);
            $params{'acquisition_date'} = $date;
        } else {
            $file->setParameter($field, $value);
            $params{$field} = $value;
        }
    }

    # Insert .ds directory content
    my @ls  = `ls $megdir/$meg`;
    my $content = join('', @ls);
    $file->setParameter('Content', $content);
    $params{'Content'}    = $content;

    return (\%params, $date);
}


=pod
Function that updates the mri_acquisition_dates table if acquisition date
for this session is already inserted.
Inputs: - $sessionID: sessionID associated with the MEG file
        - $acq_date: acquisition date of the MEG file
        - $dbhr: database handler
=cut
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

=pod
This function will rename and move the pic to the assembly folder.
Inputs: - $meg: MEG file to move
        - $subjectIDsref: hash containing subject ID's information
        - $acqProtID: acquisition protocol ID from the mri_scan_type table
        - $data_dir: root directory where to store the data (/data/project/data)
        - $prefix: prefix to be used to rename the MEG file
        - $fileref: hash containing informations relative to the meg file
Outputs:- $new_path: New path of the MEG file moved to the assembly folder
=cut
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
    my $ext         = ".tgz";
    $new_pref       =~ s/$ext//i;

    $version        = 1;
    my $extension   = "_" . sprintf("%03d",$version) . $ext;
    $new_name       = $new_pref . $extension;
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




=pod
Function that creates the pic to be associated with the file registered.
If the file is a Noise file, it will insert only the PSD image.
Else, it will merge the 3D with the PSD image and insert the merged image.
Inputs: - $meg: MEG file that will be used to determine filename of the pic
        - $pic_fold: folder containing the pics to associate to MEG file
Outputs:- undef if pic was not created
        - $pic if pic was created and found on the file system
=cut
sub create_pic {
    my ($meg, $pic_fold) = @_;

    my $meg_base    = basename($meg);
    $meg_base       =~ s/\.ds//i;

    # Read directory content of the folder containing all MEG pictures
    opendir (PICDIR, $pic_fold) || die "Cannot open $pic_fold\n";
    my @entries = readdir(PICDIR);
    closedir (PICDIR);

    # Grep the ones matching $meg_base (basename of the MEG .ds file)
    my @files_list  = grep(/$meg_base/i, @entries);
    # Add directory path to each element of the array
    @files_list     = map {"$pic_fold/" . $_} @files_list;

    # Get the 3D and PSD images to merge them into one picture
    my ($meg_3d, $meg_psd);
    foreach my $image (@files_list) {
        if ($image =~ m/MEG_3D_/i) {
            $meg_3d  = $image;
        } elsif ($image =~ m/MEG_PSD_/i) {
            $meg_psd = $image;    
        }
    }
    # Determine name of the pic to be created in the tempdir $tmp
    my $tmp = tempdir (CLEANUP => 1);
    my $pic = $tmp . "/" . $meg_base . ".jpg";
    # Return undef if could not find meg_3d or meg_psd 
    # (if meg name contains noise, return $meg_psd as no 3d are created)
    if (($meg_psd) && ($meg =~ m/Noise/i)) { 
        my $convert = "convert $meg_psd $pic";
        system ($convert);
        return undef unless (-e $pic);
        return ($pic);
    } elsif (!$meg_3d) {
        print LOG "ERROR: Could not find any MEG_3D images in $pic_fold matching $meg basename.\n";
        return undef;
    } elsif (!$meg_psd) {
        print LOG "ERROR: Could not find any MEG_PSD images in $pic_fold matching $meg basename. \n";
        return undef;
    }

    # Create picture to associate with MEG data
    my $cmd = "convert $meg_3d $meg_psd +append $pic";
    system ($cmd);
    return undef unless (-e $pic);

    return ($pic);
}
