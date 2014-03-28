#! /usr/bin/perl

use strict;
use warnings;
use Getopt::Tabular;
use File::Basename;
use FindBin;
use Date::Parse;
use XML::Simple;
use lib "$FindBin::Bin";

# These are to load the DTI & DBI modules to be used
use DB::DBI;
use DTI::DTI;

#my $xml_out = "/home/lorisdev/DTIPrep1.2.3/920912_V06/ibis_920912_V06_dti_005_XMLQCResult.xml";
#my $xml_out = "/home/lorisdev/DTIPrep1.2.3/101247_V06/ibis_101247_V06_dti_005_XMLQCResult.xml";
#my $xml_out = "/home/lorisdev/DTIPrep1.2.3/564733_V06/ibis_564733_V06_dti_001_XMLQCResult.xml";
my $xml_out = "/data/preventAD/data/pipelines/DTIPrep/DTIPrep_1.1.6_linux64/140960/NAPEN00/mri/processed/PreventAD_DTIPrep_XML_protocol/PreventAD_140960_NAPEN00_DTI_001_XMLQCResult.xml";

my ($outXMLrefs)    = &DTI::readDTIPrepXMLprot($xml_out);

sub getRejectedDirections {
    my ($outXMLrefs);

    my $tot_grads   = 0;
    my $slice_excl  = 0;
    my $grads_excl  = 0;
    my $inter_excl  = 0;
    my $tot_excl    = 0;
    my @rm_slice, @rm_interlace, @rm_intergrads;
    foreach my $key (keys $outXMLrefs->{"entry"}{"DWI Check"}{'entry'}) {
        # Next unless this is a gradient
        next unless ($key =~ /^gradient_/);

        # Grep gradient number
        my $grad_nb = $key;
        $grad_nb    =~ s/gradient_[0]+//i;

        # Grep processing status for the gradient
        my $status  = $outXMLrefs->{"entry"}{"DWI Check"}{'entry'}{$key}{'processing'};

        # Count number of gradients with different exclusion status
        if ($status =~ /EXCLUDE_SLICECHECK/i) {
            $slice_excl = $slice_excl + 1;
            push (@rm_slice, $grad_nb);
            $tot_excl   = $tot_excl + 1;
        } elsif ($status =~ /EXCLUDE_GRADIENTCHECK/i) {
            $grads_excl = $grads_excl + 1;
            push (@rm_intergrads, $grad_nb);
            $tot_excl   = $tot_excl + 1;
        } elsif ($status =~ /EXCLUDE_INTERLACECHECK/i) {
            $lace_excl  = $lace_excl + 1;
            push (@rm_interlace, $grad_nb);
            $tot_excl   = $tot_excl + 1;
        }
        $tot_grads  = $tot_grads + 1;
    }
    my $incl_grads  = $tot_grads - $tot_excl;
    my $rm_slice    = "Directions " 
                        . join(',', @rm_slice) 
                        . "(" . $slice_excl . ")";
    my $rm_intergrad= "Directions " 
                        . join(',', @rm_intergrads
                        . "(" . $grads_excl . ")";
    my $rm_interlace= "Directions " 
                        . join(',', @rm_interlace
                        . "(" . $lace_excl . ")";

    return ($rm_slice, $rm_intergrad, $rm_interlace, $tot_excl, $tot_grads, $incl_grads);

}

    if ($grads_excl > 6) {
        print "Failed due to gradient checks.\n" .
                $grads_excl . " gradients have been excluded.\n";
    } elsif ($slice_excl > 6) {
        print "Failed due to slice wise checks.\n" .
                $slice_excl . " gradients have been excluded.\n";
    } elsif ($tot_excl > 6) {
        print "Failed due to slice wise checks.\n" .
                $tot_excl . " gradients have been excluded.\n";
    } elsif ($incl_grads > 19) {
        print "Congratulations! $incl_grads gradients passed DTIPrep QC! :)\n";
    }
