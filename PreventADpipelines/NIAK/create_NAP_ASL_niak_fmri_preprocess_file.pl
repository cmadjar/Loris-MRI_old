#! /usr/bin/env perl


require 5.001;
use strict;
#use Getopt::Tabular;
use File::Basename;

### PATH definition ###
my $PREVENTAD_NIAK_DATA_FOLDER="/data/preventAD/data/pipelines/NIAK/ASL_DATA";
my $GUILLIMIN_PREVENTAD_FOLDER="/home/cmadjar/database/PreventAD/cecile/ASL_raw/DATA";

my $NIAK_script_head="/data/preventAD/data/bin/mri/PreventADpipelines/NIAK/niak_script_templates/niak_script_head.txt";
my $NIAK_script_tail="/data/preventAD/data/bin/mri/PreventADpipelines/NIAK/niak_script_templates/niak_script_NAP_tail.txt";

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =localtime(time);
my $date=sprintf("%4d%02d%02d",$year+1900,$mon+1,$mday);
my $NIAK_new_script="/data/preventAD/data/pipelines/NIAK/scripts/niak_NAP_ASL_fmri_preprocess_".$date.".m";

### create NIAK script and insert head of the script stored in $NIAK_script_head.
`/bin/cat ${NIAK_script_head} > ${NIAK_new_script}`;


#my $t='-3'; # can be 0 or +n, n being the number of days...

### Look for subjects and loop through them.
my @subjects=`/bin/ls -drt ${PREVENTAD_NIAK_DATA_FOLDER}/[0-9][0-9][0-9][0-9][0-9][0-9]`;

foreach my $subject(@subjects){
    chomp($subject);

    # Get subject name from subject's NIAK raw dataset path
    my $subject_name    = basename($subject);
    next unless ($subject_name=~m/^[0-9][0-9][0-9][0-9][0-9][0-9]$/i);

    ### Look for subject's sessions.
    my @sessions=`/usr/bin/find ${subject} -type d -name "NAP[B,F][L,U][0-9][0-9]"`;# -mtime $t`;
    # Go to the next subject if array is empty ($# returns the index of the array so -1 if empty array)
    next if ($#sessions < 0);

    foreach my $session(@sessions){
        chomp($session);

        # Get session name
        my $session_name    = basename($session);
        next unless ($session_name=~m/^NAP[B,F][L,U][0-9][0-9]$/i); 
        print "Session is: $session_name \n";

        # Determine NIAK's subject name which will regroup CandID and Visit_label information
        my $NIAK_subject    = $subject_name . "v" . $session_name;
        open FILE, ">>$NIAK_new_script" or die "Cannot open file $NIAK_new_script";
        print FILE "\n %% Subject $NIAK_subject \n";
        close FILE;

        my @files=`/bin/ls ${session}`;
        my $j=1; ### to count the number of resting state scans  
            
        foreach my $file(@files){
            chomp($file);
            my $filename=basename($file);
            if($filename=~/adniT1/m){
                open FILE, ">>$NIAK_new_script" or die "Cannot open file $NIAK_new_script";
                print FILE "files_in.s$NIAK_subject.anat                  = '$GUILLIMIN_PREVENTAD_FOLDER/$subject_name/$session_name/$filename';   %Structural scan \n";
                close FILE;
            }elsif($filename=~/ASL/m){
                open FILE, ">>$NIAK_new_script" or die "Cannot open file $NIAK_new_script";
                print FILE "files_in.s$NIAK_subject.fmri.session1.asl$j                = '$GUILLIMIN_PREVENTAD_FOLDER/$subject_name/$session_name/$filename';   % ASL run $j \n";
                close FILE;
                $j++;
            }else{
                print "$filename is neither an anatomic scan or an ASL scan"
            }
        }
        print "Done inserting Baseline files for subject $subject_name session $session_name \n";
    }
}

### add tail part of the script stored in $NIAK_script_tail.
`/bin/cat ${NIAK_script_tail} >> ${NIAK_new_script}`;

exit 0;
