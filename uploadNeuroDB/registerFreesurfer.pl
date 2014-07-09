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
    ["-freesurf_dir",   "string",   1,  \$fs_dir,   "freesurfer directory containing freesurfer outputs to be registered into the database. Should be named basename(t1)_freesurfer (i.e. r2m_476534_V00_t1_001_freesurfer)."],
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

# Remove last / from fs_dir
$fs_dir =~ s/\/$//i;

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
my $srcFileID   = &getT1FileID($fs_dir);
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
chdir(dirname($fs_dir));
my $fs_tar  = $TmpDir . "/" . basename($fs_dir) . ".tgz";
my $tar_cmd = "tar -czvf $fs_tar " . basename($fs_dir);
system($tar_cmd);
unless (-e $fs_tar) {
    print LOG "\nERROR:\n\tTar file $fs_tar of $fs_dir was not created.\n";
    exit;
}

    ##############
    ### Step 4 ###
    ##############
# Convert surfaces, thickness and create pic to associate with freesurfer tar file
my ($surfFiles)     = &createSurfaceFiles($fs_dir, $TmpDir);
&createPicFile($fs_dir, $surfFiles, $TmpDir); 
# Remove '.' in .asc files (aka lh.pial.asc will become lh_pial.asc)
&renameASCFile($surfFiles, 'asc');   # Remove '.' in surfaces filenames
&renameASCFile($surfFiles, 'thick'); # Remove '.' in thickness filenames
# Remove both.gii file from $fs_dir/surf directory
#my $gii = $fs_dir . "/surf/" . $surfFiles->{'gii'}{'both.pial'};
#my $rm  = "rm $gii";
#system($rm);
#my ($freesurfList)  = &createFreesurfList($surfFiles, $fs_dir, $TmpDir);

    ##############
    ### Step 5 ###
    ##############

# Register file into database
my @registered_fileID;
my ($FSpicFile) = &createFreesurfPic($surfFiles, $TmpDir);
foreach my $asc (keys ($surfFiles->{'asc'})) {
    my $to_register     = $surfFiles->{'asc'}{$asc};
    my $picFile         = $surfFiles->{'pic'}{$asc};
    my $thickFile       = $surfFiles->{'thick'}{$asc};
    my ($registered)    = &registerFreesurf($to_register, 
                                            $procDate,
                                            $procTool,
                                            $data_dir,
                                            $picFile,
                                            $thickFile
                                           );
    push (@registered_fileID, $registered);
}
my ($registered)    = &registerFreesurf($fs_tar, $procDate, $procTool, $data_dir, $FSpicFile);
push (@registered_fileID, $registered);


exit 0;

#####################
####  Functions  ####
#####################

=pod
Get file ID of the source t1 file used to obtain freesurfer output directory
Input: - $fs_dir    = freesurfer output directory named basename(t1)_freesurfer
Output:- $srcFileID = FileID of the t1 source file grepped from the files table 
=cut
sub getT1FileID {
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
    chomp($procTool);
    chomp($date);
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
Inputs:  - $file: freesurfer file to register
         - $procDate: processing date associate with the freesurfer outputs
         - $procTool: processing tool used to produce the freesurfer outputs
         - $data_dir: data directory (/data/project/data)
         - $picFile: pic file associated with the freesurfer tar file to register
Outputs: - $fileID: freesurfer file ID that was registered into the DB
=cut
sub registerFreesurf {
    my ($to_register, $procDate, $procTool, $data_dir, $picFile, $thickFile) = @_;
    
    # Check if tar file already registered in DB using md5sum
    my $md5check        = `md5sum $to_register`;
    my ($md5sum, $file) = split(' ',$md5check);
    my ($fileID)       = &fetchFileID($md5sum);
    # Return fsTarID if file already registered
    return ($fileID)   if ($fileID);

    # Determine source file name and source file ID
    my ($src_name)              = basename($to_register);
    $src_name   =~ s/_freesurfer\.tgz$//i;
    $src_name   =~ s/_[a-zA-Z]+h_[a-zA-Z]+\.asc$//i;
    my ($src_fileID, $reg_file) = &getSourceFileID($to_register, $src_name);
    return undef unless ($src_fileID);

    # Determine scan type
    my $scanType;
    if ($to_register =~ m/_freesurfer\.tgz$/i) {
        $scanType   = "freesurferDir";
    } elsif ($to_register =~ m/_lh_pial\.asc$/i) {
        $scanType   = "leftGMsurf";
    } elsif ($to_register =~ m/_rh_pial\.asc$/i) {
        $scanType   = "rightGMsurf";
    }

    # Set other information needed for the insertion 
    my $src_pipeline    = "freesurfer";
    my $coordinateSpace = "stereotaxic";
    my $outputType      = "processed";
    my $inputs          = $src_fileID;  # only one input, being the t1

    # Register freesurfer tar file
    ($fileID)   = &registerFile($to_register, 
                                $src_fileID,
                                $src_pipeline, 
                                $procTool,
                                $procDate, 
                                $coordinateSpace, 
                                $scanType, 
                                $outputType,
                                $inputs,
                                $picFile,
                                $thickFile
                               );

    return ($fileID);
}


=pod
Fetches the fileID of the freesurfer tar into the files table based on md5sum.
Inputs: - $md5sum: md5sum to use to find freesurfer fileID in the files table
Outputs:- $fsTarID: freesurfer fileID from the files table
=cut
sub fetchFileID {
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
sub getSourceFileID {
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
         - $src_pipeline    = Pipeline used to obtain the file (Freesurfer)
         - $src_tool        = Name and version of the tool used to obtain the file (Freesurfer-version)
         - $pipelineDate    = file's creation date (= pipeline date)
         - $coordinateSpace = file's coordinate space (= stereotaxic)
         - $scanType        = file's scan type (= processed)
         - $outputType      = file's output type (.tgz)
         - $inputs          = files that were used to create the file to be registered (intermediary files)
Outputs: - $registeredFile  = file that has been registered in the database
=cut
sub registerFile {
    my ($file, $src_fileID, $src_pipeline, $procTool, $procDate, 
        $coordinateSpace, $scanType, $outputType, $inputs, $pic, $thickFile) = @_;

    # Print LOG information about the file to be registered
    print LOG "\n\t- sourceFileID is: $src_fileID\n";
    print LOG "\t- src_pipeline is: $src_pipeline\n";
    print LOG "\t- tool is: $procTool\n";
    print LOG "\t- pipelineDate is: $procDate\n";
    print LOG "\t- coordinateSpace is: $coordinateSpace\n";
    print LOG "\t- scanType is: $scanType\n";
    print LOG "\t- outputType is: $outputType\n";
    print LOG "\t- inputFileIDs is: $inputs\n";
    print LOG "\t- associatedPic is: $pic\n";
    print LOG "\t- associatedThickness is: $thickFile\n" if ($thickFile);

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
                    "-inputFileIDs \"$inputs\" " .
                    "-associatedPic \"$pic\" "; 
    $cmd   = $cmd . "-associatedThickness \"$thickFile\" " if ($thickFile);
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






=pod
Fonction that creates and store asc surface files into a hash ($surfFiles). 
Surfaces to be converted are: (both.pial), rh.pial, lh.pial, rh.thickness, 
lh.thickness (where pial = grey matter surfaces)
Inputs: - $fs_dir: freesurfer directory containing the surfaces to be converted
Output: - $surfFiles: hash containing asc surfaces files path
=cut
sub createSurfaceFiles {
    my ($fs_dir, $TmpDir)  = @_;

    my $sub_base  = $TmpDir . "/" . basename($fs_dir);
    $sub_base     =~ s/_freesurfer$//i;
    my $surfFiles = ();
    
    # 1. Move to the surfaces directory
    chdir("$fs_dir/surf");

    # 2. Create the combined surface
#    $surfFiles->{'gii'}->{'both.pial'}= &ConvertFreesurf($fs_dir,
#                                                         "rh.pial",                # surface 
#                                                         "both.pial.gii",          # combined surfaces in gii
#                                                         "--combinesurfs lh.pial", # options
#                                                        );

    # 3. Create the combined asc file
#    my $gii = $surfFiles->{'gii'}{'both.pial'};
#    $surfFiles->{'asc'}->{'both.pial.gii'}  = &ConvertFreesurf($fs_dir,
#                                                               $gii,                        # surface
#                                                               $sub_base . "_both.pial.asc" # combined surfaces in asc
#                                                              );
#    
    # 4. Create the left surface asc file
    $surfFiles->{'asc'}->{'lh.pial'}  = &ConvertFreesurf($fs_dir,
                                                         "lh.pial",                 # left surface
                                                         $sub_base . "_lh.pial.asc" # left surface in asc
                                                        );

    # 5. Create the right surface asc file
    $surfFiles->{'asc'}->{'rh.pial'}  = &ConvertFreesurf($fs_dir,
                                                         "rh.pial",                 # right surface
                                                         $sub_base . "_rh.pial.asc" # right surface in asc
                                                        );

    # 6. Create the left thickness asc file
    $surfFiles->{'thick'}->{'lh.pial'}= &ConvertFreesurf($fs_dir,
                                                        "lh.pial",                         # left surface
                                                        $sub_base . "_lh.thickness.asc",  # left thickness in asc (output)
                                                        "-c lh.thickness"                  # options
                                                       );

    # 6. Create the left thickness asc file
    $surfFiles->{'thick'}->{'rh.pial'}= &ConvertFreesurf($fs_dir,
                                                        "rh.pial",                         # right surface
                                                        $sub_base . "_rh.thickness.asc",  # right thickness in asc (output)
                                                        "-c rh.thickness"                  # options
                                                       );
    return ($surfFiles);
}


=pod
Function that will convert surfaces and thicknesses to asc.
Inputs: - $fs_dir: freesurfer directory containing surfaces to convert
        - $surface: if want to create an asc of a surface file
        - $asc: converted surface file in asc format
        - $options: options to be used during conversion
Outputs:- $asc: converted surface file in asc format
=cut
sub ConvertFreesurf {
    my ($fs_dir, $surface, $asc, $options) = @_;    

    # convert to asc file
    my ($convert);
    if ($options) {
        $convert = "mris_convert $options $surface $asc";
    } else {
        $convert = "mris_convert $surface $asc";
    }
    print "Running $convert (...)\n";
    system($convert) unless (-e "$fs_dir/surf/$asc");

#    # If file is both.pial.asc, mris_convert creates 
#    # a file named both.both.pial.asc so move it back to both.pial.asc
#    if ($asc eq "both.pial.gii") {
#        my $cmd = "mv lh.both.pial.gii $asc";
#        system ($cmd) unless (-e "$fs_dir/surf/$asc");
#    }

    # Return output
    return undef unless ((-e "$fs_dir/surf/$asc") || (-e $asc));
    return ($asc);
}


=pod
Create the pic file of the surfaces using tksurfer.
Inputs: - $fs_dir: freesurfer directory 
        - $surfFiles: hash of the surface files to be registered into DB
        - $TmpDir: tmp directory with pic file
Outputs:- $picFile: pic file of the surface
=cut
sub createPicFile {
    my ($fs_dir, $surfFiles, $TmpDir) = @_;
    
    # 1. Move to the surfaces directory
    my $surf_dir    = $fs_dir . "/surf";
    chdir($surf_dir);
    
    # 2. Set environment and subject variables
    $ENV{'SUBJECTS_DIR'}= dirname($fs_dir);
    my $subject         = basename($fs_dir);

    # 3. Loop through surfaces and run tksurfer command to take a snapshot
    foreach my $asc (keys ($surfFiles->{'asc'})) {
        # a. determine pic name
        my $basename    = $subject;
        $basename       =~ s/_freesurfer$//i;  # Remove _freesurfer from filename to keep only subject's ID
        $basename      .= "_" . $asc;
        $basename       =~ s/\.gii$//i;  # Remove .gii at the end of filename
        $basename       =~ s/\.asc$//i;  # Remove .asc at the end of filename
        $basename       =~ s/\./_/i;     # Replace '.' by '_' in filename 
        my $picFile     = $TmpDir . "/" . $basename . ".jpg";
        # b. determine for which hemisphere command must be run
        my @split       = split('\.', $asc);
        my $hemisphere  = $split[0];
        # c. determine for which surface.extension command must be run
            # if name is hemisphere.surface (aka lh.pial)
        my $surface;
        $surface        = $split[1] if ($#split == 1);    
#            # if name is hemisphere.surface.gii (aka both.pial.gii)
#        $surface        = $split[1] . "." . $split[2] if ($#split == 2);  

        # d. run tksurfer command
        my $make_pic    = "tksurfer $subject $hemisphere $surface -snap $picFile";
        system($make_pic);
        # Somehow, the pic created by tksurfer is not readable by MRI browser
        # so convert the pic file to jpg
        my $convert     = "convert $picFile $picFile";
        system($convert);

        # e. append picFile to surfFiles hash
        $surfFiles->{'pic'}{$asc}   = $picFile;

    }
}


=pod
Function that renames asc files to remove . in middle of the name. 
Example: *lh.pial.asc will become *lh_pial.asc
Inputs: - $surfFiles: hash containing asc file paths. It will be updated with the new paths once files are renamed.
=cut
sub renameASCFile {
    my ($surfFiles, $fileType) = @_;

    foreach my $asc (keys ($surfFiles->{$fileType})){
        my $to_rename   = $surfFiles->{$fileType}{$asc};
        my $new_name    = $to_rename;
        $new_name       =~ s/\.asc$//i; #remove extension
        $new_name       =~ s/\./_/i;
        $new_name      .= ".asc";
        my $mv_cmd      = "mv $to_rename $new_name";
        system ($mv_cmd);
        $surfFiles->{$fileType}{$asc} = $new_name if (-e $new_name);
    }
}

sub createFreesurfPic {
    my ($surfFiles, $TmpDir) = @_;

    my $picFile = $TmpDir . "/FreesurferPic.jpg";
    my $lhGMpic = $surfFiles->{'pic'}{'lh.pial'};
    my $rhGMpic = $surfFiles->{'pic'}{'rh.pial'};

    my $cmd     = "convert $rhGMpic $lhGMpic +append $picFile";
    system ($cmd);

    return undef unless (-e $picFile);
    return $picFile;
}
=pod
Create freesurfer surfaces list file to associate with tar file of the 
freesurfer directory to be registered into the DB.
Inputs: - $surfFiles: hash containing the list of surfaces to insert into the list file (lh.pial.asc, rh.pial.asc, lh.thickness.asc, rh.thickness.asc, both.pial.asc)
        - $fs_dir: freesurfer directory containing the surfaces
        - $TmpDir: tmp directory in which surfaces will be moved and list of surfaces will be created
Outputs:- $freesurfList: txt file containing the list of surfaces to associate to the freesurfer directory to be registered
sub createFreesurfList { 
    my ($surfFiles, $fs_dir, $TmpDir) = @_;

    my $freesurfList    = "$TmpDir/SurfaceList.txt";
    open (FILE, ">", "$freesurfList") || die "ERROR: Cannot create file $freesurfList.\n";
    foreach my $asc (keys ($surfFiles->{'asc'})) {  
        my $surfName= $surfFiles->{'asc'}{$asc};
        my $mv      = "mv $fs_dir/surf/$surfName $TmpDir/$surfName";
        system($mv) unless (-e "$TmpDir/$surfName");
        print FILE "$asc == $TmpDir/$surfName \n";
    }
    close (FILE);

    return undef unless (-e $freesurfList);
    return ($freesurfList);
}
=cut
