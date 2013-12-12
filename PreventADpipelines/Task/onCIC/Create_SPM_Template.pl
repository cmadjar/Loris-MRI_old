#! /usr/bin/env perl

require 5.001;
use strict;
use warnings;
use Getopt::Tabular;

my $Usage = <<USAGE;

This pipeline create the SPM batch script based on a template that was created previously. The DCCID and visit label (PROVL00) will be populated automatically by this script.

Usage $0 [options]

-help for options

USAGE
my $log_dir = '/data/prevent_ad/scripts/logs';
my ($list,$SPMtemplate,@args);

my @args_table = (
    ["-list",         "string", 1, \$list,        "list of directories to use to create the SPM matlab files."],
    ["-SPM_template", "string", 1, \$SPMtemplate, "path to the SPM template to be used"],
    ["-log_dir",      "string", 1, \$log_dir,     "directory for log files"]
                 );

Getopt::Tabular::SetHelp ($Usage,'');
GetOptions(\@args_table,\ @ARGV,\@args) || exit 1;

# needed for log file
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
my $date    = sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my $log     = "$log_dir/Creation_SPM_Template$date.log";
open(LOG,">>$log");
print LOG "Log file, $date\n\n";

if (!$list) { 
    print "You need to specify a file with the list of directory to use to create the SPM matlab files.\n"; 
    exit 1;
}

if (!$SPMtemplate) { 
    print "You need to specify a SPM template to use to create the SPM matlab files.\n"; 
    exit 1;
}

open(DIRS,"<$list");
my @dirs    = <DIRS>;
close(DIRS);
foreach my $dir (@dirs){
    chomp ($dir);

    # Get site, candID and visit label
    my ($site,$candID,$visit)   = &getSiteSubjectVisitIDs($dir);
    next    if(!$site);
    print "Site \t\tCandID \t\tVisit\n$site \t$candID \t\t$visit\n";

    # Determine script to copy file name
    my ($SPM_name)  = &getCopiedFileName($SPMtemplate, $candID, $visit);
    my $SPMscript   = $dir . "/" . $SPM_name;
    print "Could not determine copied script name from $SPMtemplate for $candID $visit.\n" if (!$SPMscript);
    next    if ((!$SPMscript) || (-e $SPMscript));

    # Copy and modify template script into candID/visit
    print "Creating $SPMscript script for subject $candID, visit $visit.\n";
    my ($success)   = &copyScript($SPMtemplate, $SPMscript, $candID, $visit);
} 

exit 0;

=pod
This function extracts the site, candid and visit from the path to the ASL file given to the script.
=cut
sub getSiteSubjectVisitIDs {
    my ($d) = @_;
    if ($d =~ m/\/(\d+)\/([N,P][A,R][P,E][B,F][L,U]\d+)/i){
        my $site    ="PreventAD";
        my $candID  =$1;
        my $visit   =$2;
        return ($site, $candID, $visit);
    }else{
        return undef;
    }
}

=pod
Will determine file name of the script to copy based on $SPMtemplate, CandID and Visit.
=cut
sub getCopiedFileName {
    my ($SPMtemplate, $candID, $visit) = @_;

    # Determine copied file name based on file to copy name
    my ($prefix, $ext);
    if ($SPMtemplate =~ m/([a-zA-Z0-9]+)_DCCID_PROVL00([a-zA-Z0-9\._]+)/i) {
        $prefix = $1;
        $ext    = $2;
    }
    my $copied_file = $prefix . "_" . $candID . "_" . $visit . $ext;

    return ($copied_file);
}

=pod
Will copy the SPM template script into $candID/$visit, replace DCCID by $candID, PROVL00 by $visit and modify permissions of the copied script.
=cut
sub copyScript {
    my ($SPMtemplate, $SPMscript, $candID, $visit) = @_;

    # Copy SPM file into candID/visit directory
    `cp $SPMtemplate $SPMscript`;
    # Replace DCCID by $candID in copied script
    `grep -lr -e 'DCCID' $SPMscript | xargs perl -pi -e 's/DCCID/$candID/g'`;
    # Replace PROVL00 by $visit in copied script
    `grep -lr -e 'PROVL00' $SPMscript | xargs perl -pi -e 's/PROVL00/$visit/g'`;
    # Change permissions of the copied script to read, write and execute
    `chmod g=rwx $SPMscript`;

    if (-e $SPMscript) {
        return 1;
    } else {
        return undef;
    }

}
