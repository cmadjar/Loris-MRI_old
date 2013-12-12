#! /usr/bin/env perl


require 5.001;
use strict;
#use Getopt::Tabular;
use File::Basename;

### PATH definition ###
my $DATA_TO_TRANSFER="/data/preventAD/data/assembly";
my $NIAK_FOLDER="/data/preventAD/data/pipelines/NIAK/ASL_DATA";

#my $t='0';

my @new_T1s=`/usr/bin/find ${DATA_TO_TRANSFER} -type f -name "PreventAD_[0-9][0-9][0-9][0-9][0-9][0-9]_[N,P][A,R][P,E][B,F][L,U][0-9][0-9]_adniT1_[0-9][0-9][0-9].mnc"`;

#my @new_RSNs=`/usr/bin/find ${DATA_TO_TRANSFER} -type f -name "PreventAD_[0-9][0-9][0-9][0-9][0-9][0-9]_[N,P][A,R][P,E][B,F][L,U][0-9][0-9]_Resting_[0-9][0-9][0-9].mnc"`;

#my @new_ENCs=`/usr/bin/find ${DATA_TO_TRANSFER} -type f -name "PreventAD_[0-9][0-9][0-9][0-9][0-9][0-9]_[N,P][A,R][P,E][B,F][L,U][0-9][0-9]_Encoding_[0-9][0-9][0-9].mnc"`;

#my @new_RETs=`/usr/bin/find ${DATA_TO_TRANSFER} -type f -name "PreventAD_[0-9][0-9][0-9][0-9][0-9][0-9]_[N,P][A,R][P,E][B,F][L,U][0-9][0-9]_Retrieval_[0-9][0-9][0-9].mnc"`;

my @new_ASLs=`/usr/bin/find ${DATA_TO_TRANSFER} -type f -name "PreventAD_[0-9][0-9][0-9][0-9][0-9][0-9]_[N,P][A,R][P,E][B,F][L,U][0-9][0-9]_ASL_[0-9][0-9][0-9].mnc"`;


foreach my $new_t1(@new_T1s){
    chomp($new_t1);
    my $t1_name = basename($new_t1);
    print "$t1_name \n";
    if($t1_name =~ /(PreventAD)_([0-9][0-9][0-9][0-9][0-9][0-9])_([N,P][A,R][P,E][B,F][L,U][0-9][0-9])_(adniT1)_([0-9][0-9][0-9].mnc)/m) {
        my $DCCID = $2;
        my $visitLabel = $3;
        my $acquisition = "$4$5";
        print "mkdir $DCCID \n";
        `mkdir $NIAK_FOLDER/$DCCID` unless -e "$NIAK_FOLDER/$DCCID"; 
        `mkdir $NIAK_FOLDER/$DCCID/$visitLabel` unless -e "$NIAK_FOLDER/$DCCID/$visitLabel";
        print "cp $new_t1 $NIAK_FOLDER/$DCCID/$visitLabel/$1_$DCCID\_$visitLabel\_$acquisition \n";    
        `cp $new_t1 $NIAK_FOLDER/$DCCID/$visitLabel/$1_$DCCID\_$visitLabel\_$acquisition` unless -e "$NIAK_FOLDER/$DCCID/$visitLabel/$1_$DCCID\_$visitLabel\_$acquisition";
    }else{
        print "T1 file $new_t1 does not fit labeling requirement \n";    
    }
}

#foreach my $new_rsn(@new_RSNs){
#    chomp($new_rsn);
#    my $rsn_name = basename($new_rsn);
#    print "$rsn_name \n";
#    if($rsn_name =~ /(PreventAD)_([0-9][0-9][0-9][0-9][0-9][0-9])_([N,P][A,R][P,E][B,F][L,U][0-9][0-9])_(Resting)_([0-9][0-9][0-9].mnc)/m) {
#        my $DCCID = $2;
#        my $visitLabel = $3;
#        my $acquisition = "$4$5";
#        print "mkdir $DCCID \n";
#        `mkdir $NIAK_FOLDER/$DCCID` unless -e "$NIAK_FOLDER/$DCCID";
#        `mkdir $NIAK_FOLDER/$DCCID/$visitLabel` unless -e "$NIAK_FOLDER/$DCCID/$visitLabel";
#        print "cp $new_rsn $NIAK_FOLDER/$DCCID/$visitLabel/$1_$DCCID\_$visitLabel\_$acquisition \n";    
#        `cp $new_rsn $NIAK_FOLDER/$DCCID/$visitLabel/$1_$DCCID\_$visitLabel\_$acquisition` unless -e "$NIAK_FOLDER/$DCCID/$visitLabel/$1_$DCCID\_$visitLabel\_$acquisition";
#    }else{
#        print "RSN file $new_rsn does not fit labeling requirement \n";
#    }
#}

#foreach my $new_enc(@new_ENCs){
#    chomp($new_enc);
#    my $enc_name = basename($new_enc);
#    print "$enc_name \n";
#    if($enc_name =~ /(PreventAD)_([0-9][0-9][0-9][0-9][0-9][0-9])_([N,P][A,R][P,E][B,F][L,U][0-9][0-9])_(Encoding)_([0-9][0-9][0-9].mnc)/m) {
#        my $DCCID = $2;
#        my $visitLabel = $3;
#        my $acquisition = "$4$5";
#        print "mkdir $DCCID \n";
#        `mkdir $NIAK_FOLDER/$DCCID` unless -e "$NIAK_FOLDER/$DCCID";
#        `mkdir $NIAK_FOLDER/$DCCID/$visitLabel` unless -e "$NIAK_FOLDER/$DCCID/$visitLabel";
#        print "cp $new_enc $NIAK_FOLDER/$DCCID/$visitLabel/$1_$DCCID\_$visitLabel\_$acquisition \n";
#        `cp $new_enc $NIAK_FOLDER/$DCCID/$visitLabel/$1_$DCCID\_$visitLabel\_$acquisition` unless -e "$NIAK_FOLDER/$DCCID/$visitLabel/$1_$DCCID\_$visitLabel\_$acquisition";
#    }else{
#        print "Encoding file $new_enc does not fit labeling requirement \n";
#    }
#}
#
#foreach my $new_ret(@new_RETs){
#    chomp($new_ret);
#    my $ret_name = basename($new_ret);
#    print "$ret_name \n";
#    if($ret_name =~ /(PreventAD)_([0-9][0-9][0-9][0-9][0-9][0-9])_([N,P][A,R][P,E][B,F][L,U][0-9][0-9])_(Retrieval)_([0-9][0-9][0-9].mnc)/m) {
#        my $DCCID = $2;
#        my $visitLabel = $3;
#        my $acquisition = "$4$5";
#        print "mkdir $DCCID \n";
#        `mkdir $NIAK_FOLDER/$DCCID` unless -e "$NIAK_FOLDER/$DCCID";
#        `mkdir $NIAK_FOLDER/$DCCID/$visitLabel` unless -e "$NIAK_FOLDER/$DCCID/$visitLabel";
#        print "cp $new_ret $NIAK_FOLDER/$DCCID/$visitLabel/$1_$DCCID\_$visitLabel\_$acquisition \n";
#        `cp $new_ret $NIAK_FOLDER/$DCCID/$visitLabel/$1_$DCCID\_$visitLabel\_$acquisition` unless -e "$NIAK_FOLDER/$DCCID/$visitLabel/$1_$DCCID\_$visitLabel\_$acquisition";
#    }else{
#        print "Retrieval file $new_ret does not fit labeling requirement \n";
#    }
#}
#
foreach my $new_asl(@new_ASLs){
    chomp($new_asl);
    my $asl_name = basename($new_asl);
    print "$asl_name \n";
    if($asl_name =~ /(PreventAD)_([0-9][0-9][0-9][0-9][0-9][0-9])_([N,P][A,R][P,E][B,F][L,U][0-9][0-9])_(ASL)_([0-9][0-9][0-9].mnc)/m) {
        my $DCCID = $2;
        my $visitLabel = $3;
        my $acquisition = "$4$5";
        print "mkdir $DCCID \n";
        `mkdir $NIAK_FOLDER/$DCCID` unless -e "$NIAK_FOLDER/$DCCID";
        `mkdir $NIAK_FOLDER/$DCCID/$visitLabel` unless -e "$NIAK_FOLDER/$DCCID/$visitLabel";
        print "cp $new_asl $NIAK_FOLDER/$DCCID/$visitLabel/$1_$DCCID\_$visitLabel\_$acquisition \n";
        `cp $new_asl $NIAK_FOLDER/$DCCID/$visitLabel/$1_$DCCID\_$visitLabel\_$acquisition` unless -e "$NIAK_FOLDER/$DCCID/$visitLabel/$1_$DCCID\_$visitLabel\_$acquisition";
    }else{
        print "ASL file $new_asl does not fit labeling requirement \n";
    }
}


