#! /usr/bin/env perl

require 5.001;
use strict;
use warnings;
use Getopt::Tabular;

my $Usage = <<USAGE;

This pipeline copy mat files stored in a folder and distribute them according to their DCCID and visit label. 

Usage $0 [options]

-help for options

USAGE
my $log_dir = '/data/prevent_ad/SPM_script/logs';
my ($dir, $analyses,@args);

my @args_table = (
    ["-dir",          "string",   1,  \$dir,      "directory containing matlab files to copy."],
    ["-analyses_dir", "string",   1,  \$analyses, "path to the analyses directory containing MRI imagess"],
    ["-log_dir",      "string",   1,  \$log_dir,  "directory for log files"],
                 );

Getopt::Tabular::SetHelp ($Usage,'');
GetOptions(\@args_table,\ @ARGV,\@args) || exit 1;

# needed for log file
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
my $date    = sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my $log     = "$log_dir/Copy_mat_files_$date.log";
open(LOG,">>$log");
print LOG "Log file, $date\n\n";

if(!$dir) { 
    print "You need to specify a directory to look for matlab files to copy.\n"; 
    exit 1;
}

if(!$analyses) { 
    print "You need to specify the ANALYSES directory in which to copy matlab files.\n"; 
    exit 1;
}

opendir (DIR,"$dir") || die "Cannot open $dir\n";
my @entries   = readdir (DIR);
close(DIR);

my @to_copy   = grep (/\.mat$/i, @entries);

foreach my $file (@to_copy) {

    chomp ($file);
    my ($run, $candID, $visit)  = &getSubjIDs($file);
    next    if((!$run) || (!$candID) || (!$visit));
    print LOG "fMRI \t\tCandID \t\tVisit\n$run \t$candID \t\t$visit\n";
    print     "fMRI \t\tCandID \t\tVisit\n$run \t$candID \t\t$visit\n";

    print LOG "Copying .mat file for subject $candID, visit $visit, fMRI $run.";
    print     "Copying .mat file for subject $candID, visit $visit, fMRI $run.";

    # create directory regression in $candID/$visit
    `mkdir $analyses/$candID/$visit/regression`;

    # copy matlab files into candID, visit label directory
    `cp $dir/$file $analyses/$candID/$visit/regression`;

    # change permissions of regression directory
    `chmod -R g=rwx $analyses/$candID/$visit/regression`;

} 

exit 0;



############
# Function #
############

=pod
This function extracts the fMRI run, candid and visit information from the filename.
=cut
sub getSubjIDs {
    my ($file) = @_;

    if ($file =~ m/^([a-zA-Z]+)_reg_cond_(\d\d\d\d\d\d)_([N,P][A,R][P,E][B,F][L,U]\d\d).mat$/i){
        my $run     = $1;
        my $candID  = $2;
        my $visit   = $3;
        return($run, $candID, $visit);
    }else{
        return undef;
    }

}

