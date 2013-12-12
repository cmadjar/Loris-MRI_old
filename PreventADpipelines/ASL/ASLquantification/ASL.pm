=pod

=head1 NAME

ASL -- A set of utility functions to perform ASL quantification.

=head1 SYNOPSIS

 use ASL;

=head1 DESCRIPTION

This is a mismatch of functions that are used to run ASL quantification. 
This is called by ASLpreprocessing.pl.

=head1 METHODS

=cut

package ASL;

use Exporter();
use File::Temp qw(tempdir);
use XML::Simple;
use File::Basename;

$VERSION    = 0.0;
@ISA        = qw(Exporter);

@EXPORT     = qw();
@EXPORT_OK  = qw(getSiteSubjectVisitIDs getOutputNames getParameter);


=pod

This function extracts the site, candid and visit from the path to the ASL file given to the script.

=cut

sub getSiteSubjectVisitIDs {
    my ($d)=@_;
    if ($d=~m/ASL\/DATA\/(\d+)\/([N,P][A,R][P,E][B,F][L,U]\d+)/i){
        my $site="PreventAD";
        my $candID=$1;
        my $visit=$2;
        return($site,$candID,$visit);
    }else{
        return undef;
    }
}

=pod

This function determines the output names based on which plugin will be run.

=cut

sub getOutputNames {
    my ($filename,$outdir,$nldo_opt)=@_;
    
    my ($pre_flow_suffix,$pre_even_suffix);
    foreach my $plug (@{$nldo_opt->{plugin}}){
        if ($plug->{name} eq 'Motion Correction'){
            $pre_flow_suffix="-MC";
            $pre_even_suffix="-MC";
            next;
        }
        if ($plug->{name} eq 'ASL Subtraction'){
            $pre_flow_suffix=$pre_flow_suffix."-flow";
            $pre_even_suffix=$pre_even_suffix."-even";
            next;
        }
        if ($plug->{name} eq 'Spatial Filtering'){
            $pre_flow_suffix=$pre_flow_suffix."-SM";
            $pre_even_suffix=$pre_even_suffix."-SM";
            next;
        }
    }
    my $preprocessed_flow=$outdir."/".substr(basename($filename),0,-4).$pre_flow_suffix.".mnc";
    my $preprocessed_even=$outdir."/".substr(basename($filename),0,-4).$pre_even_suffix.".mnc";
    my $flow_eff=substr($preprocessed_flow,0,-4)."-eff.mnc";
    my $even_eff=substr($preprocessed_even,0,-4)."-eff.mnc";
    my $cbf_map=substr($flow_eff,0,-4)."-cbf.mnc";
    print "\n\n$cbf_map\n\n";
    return ($preprocessed_flow,$preprocessed_even,$flow_eff,$even_eff,$cbf_map);
}

=pod

This function reads the xml file filled with analysis' options to use and returns the options in a string.

=cut

sub getParameters{
    my ($nldo_opt, $plug)=@_;
    
    # read the XML file with analyses parameters
#    my $xml = new XML::Simple (KeyAttr=>[]);
#    my $data = $xml->XMLin($xml_file);

    # dereference hash ref
    # access <plugin> array
    my %parameters_list;
    my $outputs_list;
    my $options;
    foreach my $plugin (@{$nldo_opt->{plugin}}){
        next unless ($plugin->{name} eq $plug); 
        my @parameters_list=@{$plugin->{parameter}};
        foreach my $p (@parameters_list){
            if ($p->{name} eq "-subtractionOrder" ||
                $p->{name} eq "-kernelType"       ||
                $p->{name} eq "-contrastList"     ||
                $p->{name} eq "-interpolationType"||
                $p->{name} eq "-aslType"
                )
                {$options = $options." ".$p->{name}." \"".$p->{value}."\"";next;}
            $options = $options." ".$p->{name}." ".$p->{value};
        }
    }
    return $options;
}

