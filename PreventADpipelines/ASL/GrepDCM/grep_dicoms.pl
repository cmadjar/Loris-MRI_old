use strict;
use Getopt::Tabular;
use FileHandle;
use File::Basename;
use File::Temp qw/ tempdir /;
use FindBin;




## needed for log and template
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =localtime(time);
my $date        = sprintf("%4d-%02d-%02d %02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my $profile     = undef;
my $pattern     = undef;
my $tarchive    = undef;


my @opt_table = (
                 ["Basic options","section"],
                 ["-profile"    ,"string", 1, \$profile, "name of config file in ~/.neurodb."],

                 ["Advanced options","section"],
                 ["-pattern"    ,"string", 1, \$pattern, "Pattern to use to grep DICOM files (typically, the series description)."],
                 ["-tarchive"   ,"string", 1, \$tarchive,"Tarchive file to parse."],
                );

my $Help = <<HELP;
This takes the tarchive and grep for a specific pattern. Both the tarchive and the pattern need to be specified in the option.

HELP
my $Usage   = <<USAGE;
usage: $0 [options]
       $0 -help to list options

USAGE
&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV) || exit 1;

# input option error checking
{ package Settings; do "$ENV{HOME}/.neurodb/$profile" }
if ($profile && !defined @Settings::db) { print "\n\tERROR: You don't have a configuration file named '$profile' in:  $ENV{HOME}/.neurodb/ \n\n"; exit 33; }
if(!$tarchive || !$pattern || !$profile) { print $Help; print "$Usage\n\tERROR: You must specify a valid tarchive, a pattern to grep for in the DICOMs and an existing profile.\n\n";  exit 33;  }

# These settings are in a config file (profile)
my $data_dir            = $Settings::data_dir;
my $tarchiveLibraryDir  = $Settings::tarchiveLibraryDir;
my $mail_user           = $Settings::mail_user;
my $template            = "TarGrep-$hour-$min-XXXXXX"; # for tempdir

# Check that tarchive file exists
unless (-e "$tarchiveLibraryDir/$tarchive") {
    print "\nERROR: Could not find archive $tarchive. \nPlease, make sure the path to the archive is correct. Upload will exit now.\n\n\n";
    exit 33;
}
my $tarchive_path   = $tarchiveLibraryDir . "/" . $tarchive;

# create the temp dir
my $TmpDir = tempdir($template, TMPDIR => 1, CLEANUP => 1 );

# create logdir(if !exists) and logfile
my @temp     = split(/\//, $TmpDir);
my $templog  = $temp[$#temp];
my $LogDir   = "$data_dir/logs"; if (!-d $LogDir) { mkdir($LogDir, 0700); }
my $logfile  = "$LogDir/$templog.log";
open LOG, ">$logfile";
LOG->autoflush(1);
&logHeader();


## Extract tarchive in tmp directory
my $study_dir   = $TmpDir . "/" . extract_tarchive($tarchive, $TmpDir);
my $grepped_dir = grep_dicom($study_dir, $TmpDir, $pattern);
if (!$grepped_dir) {
    print LOG "\nERROR: could not find any DICOM containing $pattern in $study_dir.\n";
    exit;
} 
my $moved_tar   = tar_and_move_dicom($study_dir, $grepped_dir, $TmpDir, $data_dir);
if ($moved_tar == 1) {
    print LOG "\nERROR: could not determine pscid, dccid, visit label and date of the study $study_dir\n";
} elsif ($moved_tar == 2) {
    print LOG "\nERROR: DICOM folder could not be tarred.\n";    
} else {
    print LOG "\nDone! $moved_tar\n";
}

#############
# Functions #
#############

# Most important function now. Gets the tarchive and extracts it so data can actually be uploaded
sub extract_tarchive {
    my ($tarchive, $tempdir) = @_;
    print "Extracting tarchive\n" if $verbose;
    `cd $tempdir ; tar -xf $tarchive`;
    opendir TMPDIR, $tempdir;
    my @tars = grep { /\.tar\.gz$/ && -f "$tempdir/$_" } readdir(TMPDIR);
    closedir TMPDIR;
    if(scalar(@tars) != 1) {
        print "Error: Could not find inner tar in $tarchive!\n";
        print @tars . "\n";
        exit(1);
    }
    my $dcmtar = $tars[0];
    my $dcmdir = $dcmtar;
    $dcmdir =~ s/\.tar\.gz$//;

    `cd $tempdir ; tar -xzf $dcmtar`;
    `rm $tempdir/$dcmdir/S*`;
    return $dcmdir;
}

sub grep_dicom {
    my ($study_dir, $TmpDir, $pattern) = @_;

    my $study_name  = basename($study_dir);
    my $grepped_dir = $TmpDir . "/" $study_name . "_" . $pattern;
    mkdir ($grepped_dir, 0755);

    my $grep_cmd    = "grep -lr $pattern $study_name | while read f; do cp \$f $grepped_dir; done";
    system($grep_cmd);

    opendir GREPDIR, $grepped_dir;
    my @matches     = grep { /\d[A-Za-z]/ && -f "$tempdir/$_" } readdir(GREPDIR);
    close GREPDIR;
    if (scalar($matches) < 1) {
        return undef;
    } else {
        return $grepped_dir;
    }
}


sub tar_and_move_dicom { 
    my ($study_dir, $grepped_dir, $TmpDir, $data_dir) = @_;

    my $study_name  = basename($study_dir);
    my ($pscid, $dccid, $visit_label, $date);
    if ($study_name =~ m/([^_]+)_(\d+)_([^_]+)_(\d+)/i) {
        $pscid       = $1;
        $dccid       = $2;
        $visit_label = $3;
        $date        = $4;
    } else {
        return 1;
    }

    my $new_dir     = $data_dir . "/pipelines/ASL/raw_dicom/" .
                      $dccid    . "/" .
                      $visit_label;
    make_path($new_dir, {mode => 0750});
    my $inc         = 1;
    my $to_tar      = basename($grepped_dir);
    my $tarname     = $to_tar . "_" . $inc . ".tgz";
    while (-e $tarname) {
        $inc        =+ 1;
        $tarname    = $to_tar . "_" . $inc . ".tgz";
    }

    chdir($TmpDir);
    my $tar_cmd     = "tar -czf $new_dir/$tarname $to_tar";

    if (-e "$new_dir/$tarname") {
        return $tarname;    
    } else {
        return 2;
    }
}
