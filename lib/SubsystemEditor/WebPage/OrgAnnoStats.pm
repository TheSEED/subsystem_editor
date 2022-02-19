package SubsystemEditor::WebPage::OrgAnnoStats;

use base qw( WebPage );

use FIG_Config;

use URI::Escape;

use strict;
use warnings;

use Tracer;
use HTML;
use FFs;
use FIGRules;

use Data::Dumper;

1;

=pod

=head1 NAME

Annotation - an instance of WebPage which displays information about an Annotation

=head1 DESCRIPTION

Display information about an Annotation

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title( 'Organism Annotation Overview' );
  $self->application->register_component( 'Table', 'AnnoTable' );
  $self->application->register_component( 'FilterSelect', 'OrganismSelect' );

  return 1;
}

=item * B<output> ()

Returns the html output of the Annotation page.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $fig = $application->data_handle('FIG');

  my $content;

  my $organism = $cgi->param( 'organism' );
  if ( !defined( $organism ) ) { 

    my $genomes = $fig->genome_info();
    my @genomessorted = sort { $a->[1] cmp $b->[1] } @$genomes;
    my @genomelabels = map { $_->[1] . '( '. $_->[0].' )' } @genomessorted;
    my @genomevalues = map { $_->[0] } @genomessorted;
    
    # create the select organism component
    my $organism_select_component = $self->application->component( 'OrganismSelect' );
    $organism_select_component->labels( \@genomelabels );
    $organism_select_component->values( \@genomevalues );
    $organism_select_component->name( 'organism' );
    $organism_select_component->width(500);

    $content .= "<H1>Annotation Overview</H2>";
    $content .= $self->start_form();
#    $content .= "<INPUT TYPE=TEXT NAME='organism' ID='organism'><INPUT TYPE=SUBMIT VALUE='Show'>";
    $content .= $organism_select_component->output();
    $content .= "<INPUT TYPE=SUBMIT VALUE='Show'>";
    $content .= $self->end_form();
    return $content;
  }

  my $genus_species = $fig->genus_species( $organism );
  $content .= "<H1>Annotation Overview for Organism $genus_species ( $organism )</H2>";

  my @annos = $fig->read_all_annotations( $organism );
  my @data;

  foreach my $ann ( @annos ) {
    next if $ann->[2] eq 'rapid_propogation';
    next if $ann->[2] eq 'annotation_repair';
    next if $ann->[3] =~ /^Role changed from/;
    next if $ann->[3] =~ /^Master function set by/;

    my $time = &FIG::epoch_to_readable( $ann->[1] );

    my $figidlink = "<a href='seedviewer.cgi?page=Annotation&feature=".$ann->[0]."'>".$ann->[0]."</a>";
    push @data, [ $figidlink, $time, $ann->[2], $ann->[3] ];
  
  }

  my $table = $application->component( 'AnnoTable' );

  $table->show_top_browse( 1 );
  $table->show_bottom_browse( 1 );
  $table->show_export_button( 1 );
  $table->columns( [ { 'name' => 'Feature', 'sortable' => 1, 'filter' => 1 },
		     { 'name' => 'Time', 'sortable' => 1, 'filter' => 1 },
		     { 'name' => 'User', 'sortable' => 1, 'filter' => 1 },
		     { 'name' => 'Data', 'sortable' => 1, 'filter' => 1 } ] );

  $table->data( \@data );

  $content .= $table->output();

#  foreach my $ann ( @annos ) {
#    $content .= $ann." \n";
#  }

  return $content;
}
