#! /usr/bin/env perl


require 5.001;
use strict;
#use Getopt::Tabular;
use File::Basename;

### PATH definition ###
my $PREVENTAD_NIAK_DATA_FOLDER="/data/preventAD/data/pipelines/NIAK/DATA";
my $GUILLIMIN_PREVENTAD_FOLDER="/home/cmadjar/database/PreventAD/raw_data";

my $NIAK_script_head="/data/preventAD/data/bin/mri/PreventADpipelines/NIAK/niak_script_templates/niak_script_head.txt";
my $NIAK_script_tail="/data/preventAD/data/bin/mri/PreventADpipelines/NIAK/niak_script_templates/niak_script_tail.txt";

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =localtime(time);
my $date=sprintf("%4d%02d%02d",$year+1900,$mon+1,$mday);
my $NIAK_new_script="/data/preventAD/data/pipelines/NIAK/scripts/niak_fmri_preprocess_".$date.".m";

### create NIAK script and insert head of the script stored in $NIAK_script_head.
`/bin/cat ${NIAK_script_head} > ${NIAK_new_script}`;


my $t='-3'; # can be 0 or +n, n being the number of days...

### Look for subjects and loop through them.
my @subjects=`/bin/ls -d ${PREVENTAD_NIAK_DATA_FOLDER}/[0-9][0-9][0-9][0-9][0-9][0-9]`;

my $i=1;
foreach my $subject(@subjects){

    chomp($subject);
    my $subject_name=basename($subject);
    print "Subject is: $subject_name \n";
   
    open(FILE, ">>$NIAK_new_script") or die "Cannot open file $NIAK_new_script";
    print FILE "\n %% Subject $subject_name \n";
    close(FILE);

    ### Look for subject's sessions and look through them.
    my @sessions=`/usr/bin/find ${subject} -type d -name "[N][A][P][B,F][L,U][0-9][0-9]" `;

    foreach my $session(@sessions){

        chomp($session);
        my $session_name=basename($session); 

	print "Session is $session_name\n";
        if($session=~m/BL00$/i){
            print "Session is: $session_name \n";

            my @files=`/bin/ls ${session}`;
            my $j=1; ### to count the number of resting state scans  
            
            foreach my $file(@files){
                
                chomp($file);
		print "File is $file\n";
                my $filename=basename($file);
                
                if($filename=~m/adniT1/i){
                    
                    open(FILE, ">>$NIAK_new_script") or die "Cannot open file $NIAK_new_script";
                    print FILE "files_in.s$subject_name.anat                  = '$GUILLIMIN_PREVENTAD_FOLDER/$subject_name/$session_name/$filename';   %Strucutral scan \n";
                    close(FILE);
		    print "YOUHOU T1 is $filename \n";
                    print "files_in.s$subject_name.anat                  = '$GUILLIMIN_PREVENTAD_FOLDER/$subject_name/$session_name/$filename';   %Strucutral scan \n";
                
                }elsif($filename=~m/Resting/i){
                    
                    open (FILE, ">>$NIAK_new_script") or die "Cannot open file $NIAK_new_script";
                    print FILE "files_in.s$subject_name.fmri.$session_name.rest$j                = '$GUILLIMIN_PREVENTAD_FOLDER/$subject_name/$session_name/$filename';   % Resting fMRI run $j \n";
                    close (FILE);
                    $j++;
                    print "files_in.s$subject_name.fmri.$session_name.rest$j                = '$GUILLIMIN_PREVENTAD_FOLDER/$subject_name/$session_name/$filename';   % Resting fMRI run $j \n";
                
                }else{
                
                    print "$filename is neither an anatomic scan or a resting scan"
                
                }
            }
            print "Done inserting Baseline files for subject $subject_name session $session_name \n";
        } elsif ($session=~m/FU/i) {
	    print "Session is: $session_name \n";
	    
	    my @files=`/bin/ls ${session}`;
            my $j=1; ### to count the number of resting state scans  

            foreach my $file(@files){

                chomp($file);
                print "File is $file\n";
                my $filename=basename($file);

                if($filename=~m/Resting/i){

                    open (FILE, ">>$NIAK_new_script") or die "Cannot open file $NIAK_new_script";
                    print FILE "files_in.s$subject_name.fmri.$session_name.rest$j                = '$GUILLIMIN_PREVENTAD_FOLDER/$subject_name/$session_name/$filename';   % Resting fMRI run $j \n";
                    close (FILE);
                    $j++;
                    print "files_in.s$subject_name.fmri.$session_name.rest$j                = '$GUILLIMIN_PREVENTAD_FOLDER/$subject_name/$session_name/$filename';   % Resting fMRI run $j \n";

                }else{

                    print "$filename is neither an anatomic scan or a resting scan"

                }
	    }
	} 
    }
    $i++;
}

### add tail part of the script stored in $NIAK_script_tail.
`/bin/cat ${NIAK_script_tail} >> ${NIAK_new_script}`;
