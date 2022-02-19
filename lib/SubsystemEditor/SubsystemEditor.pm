package SubsystemEditor::SubsystemEditor;

use strict;
use warnings;

use base qw( Exporter );
our @EXPORT = qw ( fid_link moregenomes );

1;



sub fid_link {
    my ( $page, $fid ) = @_;
    my $n;

    if ($fid =~ /^fig\|\d+\.\d+\.([a-zA-Z]+)\.(\d+)/) {
      if ( $1 eq "peg" ) {
	  $n = $2;
	}
      else {
	  $n = "$1.$2";
	}
    }

#    return "./protein.cgi?prot=$fid&user=$seeduser\&new_framework=0";
    return "./seedviewer.cgi?page=Annotation&feature=$fid&user=".$page->{ 'seeduser' };
}

sub moregenomes {
  my ( $page, $more ) = @_;
  
  if ( $more eq "Cyanobacteria" )              { return &selectgenomeattr( $page->{ 'fig' }, "phylogeny", "Cyanobacteria" ) }
  if ( $more eq "NMPDR" )                      { return &selectgenomeattr( $page->{ 'fig' }, "filepresent", "NMPDR" ) }
  if ( $more eq "BRC" )                        { return &selectgenomeattr( $page->{ 'fig' }, "filepresent", "BRC" ) }
  if ( $more eq "higher_plants" )              { return &selectgenomeattr( $page->{ 'fig' }, "higher_plants" ) }
  if ( $more eq "eukaryotic_ps" )              { return &selectgenomeattr( $page->{ 'fig' }, "eukaryotic_ps" ) }
  if ( $more eq "nonoxygenic_ps" )             { return &selectgenomeattr( $page->{ 'fig' }, "nonoxygenic_ps" ) }
  if ( $more eq "Hundred by a hundred" )       { return &selectgenomeattr( $page->{ 'fig' }, "hundred_hundred" ) }
  if ( $more eq "functional_coupling_paper" )  { return &selectgenomeattr( $page->{ 'fig' }, "functional_coupling_paper" ) }
  if ( $more eq "Eukaryotic virus" )  { return &selectgenomeattr( $page->{ 'fig' }, "virus_type", "Eukaryotic" ) }
  if ( $more eq "Phage" )  { return &selectgenomeattr( $page->{ 'fig' }, "virus_type", "Phage" ) }
}

sub selectgenomeattr {
  my ( $fig, $tag, $value )=@_;
  my @orgs;

  if ( $tag eq "phylogeny" ) {
    my $taxonomic_groups = $fig->taxonomic_groups_of_complete(10);
    foreach my $pair (@$taxonomic_groups)
      { 
	push @orgs, @{$pair->[1]} if ($pair->[0] eq "$value");
      }
  }
  elsif ( $tag eq "filepresent" ) {
    foreach my $genome ( $fig->genomes ) {
      push(@orgs, $genome) if (-e $FIG_Config::organisms."/$genome/$value");
    }
  }
  else {
    if ( $value ) {
      @orgs = map { $_->[0]} grep {$_->[0] =~ /^\d+\.\d+$/ } $fig->get_attributes( undef, $tag, $value );
    }
    else {
      @orgs = map { $_->[0]} grep {$_->[0] =~ /^\d+\.\d+$/ } $fig->get_attributes( undef, 'collection', $tag );
    }
  }
  return @orgs;
}
