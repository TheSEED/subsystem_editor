package SubsystemEditor::WebPage::GenesForColumn;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;

use FIG;
use FIGV;
use UnvSubsys;
use FFs;

use base qw( WebPage );

1;

##################################################
# Method for registering components etc. for the #
# application                                    #
##################################################
sub init {
  my ( $self ) = @_;

  $self->application->register_component( 'Table', 'PegTable' );
  $self->application->register_component( 'Info', 'CommentInfo');
}

sub require_javascript {

  return [ './Html/showfunctionalroles.js' ];

}

##############################################
# Website content is returned by this method #
##############################################
sub output {
  my ( $self ) = @_;

  # needed objects #
  my $application = $self->application();
  $self->{ 'fig' } = $application->data_handle( 'FIG' );
  $self->{ 'cgi' } = $application->cgi;
  
  # subsystem name and 'nice name' #
  my $name = $self->{ 'cgi' }->param( 'subsystem' );
  my $ssname = $name;
  $ssname =~ s/\_/ /g;

  # get a subsystem object to handle it #
  my $subsystem = new Subsystem( $name, $self->{ 'fig' }, 0 );

  my $funcrole = $self->{ 'cgi' }->param( 'fr' );
  if ( !defined( $name ) || $name eq '' ) {
    undef $name;
    $self->application->add_message( 'warning', 'No subsystem given<BR>' );
  }
  if ( !defined( $funcrole ) || $funcrole eq '' ) {
    undef $funcrole;
    $self->application->add_message( 'warning', 'No functional role given<BR>' );
  }
  if ( !defined( $name ) || !defined( $funcrole ) ) {
    return "<H1>Genes for Column</H1>";
  }

  my $fr = $funcrole;

  my $showminus = $self->{ 'cgi' }->param( 'showminus' );

  # look if someone is logged in and can write the subsystem #
  $self->{ 'can_alter' } = 0;
  my $user = $self->application->session->user;

  my $dbmaster = $self->application->dbmaster;
  my $ppoapplication = $self->application->backend;
  
  # get a seeduser #
  $self->{ 'seeduser' } = '';
  if ( defined( $user ) && ref( $user ) ) {
    my $preferences = $dbmaster->Preferences->get_objects( { user => $user,
							     name => 'SeedUser',
							     application => $ppoapplication } );
    if ( defined( $preferences->[0] ) ) {
      $self->{ 'seeduser' } = $preferences->[0]->value();
    }
  }

  if ( $user && $user->has_right( $self->application, 'edit', 'subsystem', $name ) ) {
    $self->{ 'can_alter' } = 1;
    $self->{ 'fig' }->set_user( $self->{ 'seeduser' } );
  }

  $self->title( "Genes for Column" );

  my ( $error, $comment ) = ( "", "" );

  #########
  # TASKS #
  #########

  if ( defined( $self->{ 'cgi' }->param( 'actionhidden' ) ) && $self->{ 'cgi' }->param( 'actionhidden' ) eq 'Replace' ) {
    my @genes = $self->{ 'cgi' }->param( 'cds_checkbox' );
    my $newfunc = $self->{ 'cgi' }->param( 'RPTEXT' );
    my $repstring = $self->{ 'cgi' }->param( 'QUERYTEXT' );
    if ( !defined( $self->{ 'seeduser' } ) ) {
      $error = "No username defined for that action<BR>\n";
    }
    elsif ( !defined( $newfunc ) || $newfunc eq '' || $newfunc eq ' ' ) {
      $error = "No new function given to replace with<BR>\n";
    }
    else {
      foreach my $g ( @genes ) {
	$g =~ /(fig\|\d+\.\d+\.peg\.\d+)/;

	my $thispeg = $1;
	# get current function of peg
	my $currfunction = $self->{ 'fig' }->function_of( $thispeg );
	if ( index( $currfunction, $repstring ) >= 0 ) {
 	  $currfunction =~ s/$repstring/$newfunc/g;

	  if ( $self->{ 'fig' }->assign_function( $thispeg, $self->{ 'seeduser' }, $currfunction, "" ) ) {
	    $comment .= "Added Annotation $currfunction to $thispeg<BR>\n";
	  }
	  else {
	    $error .= "Could not change function of $thispeg to $currfunction<BR>\n";
	  }
	}
	else {
	  $error .= "$repstring not found in $currfunction<BR>\n";
	}
      }
    }
  }
  if ( defined( $self->{ 'cgi' }->param( 'actionhidden' ) ) && $self->{ 'cgi' }->param( 'actionhidden' ) eq 'Rename' ) {
    my @genes = $self->{ 'cgi' }->param( 'cds_checkbox' );
    my $newfunc = $self->{ 'cgi' }->param( 'FRTEXT' );
    if ( !defined( $self->{ 'seeduser' } ) ) {
      $error = "No username defined for that action<BR>\n";
    }
    elsif ( !defined( $newfunc ) || $newfunc eq '' || $newfunc eq ' ' ) {
      $error = "No new function given to rename<BR>\n";
    }
    else {
      foreach my $g ( @genes ) {
	$g =~ /(fig\|\d+\.\d+\.peg\.\d+)/;
	if ( $self->{ 'fig' }->assign_function( $1, $self->{ 'seeduser' }, $newfunc, "" ) ) {
	  $comment .= "Added Annotation $newfunc to $1<BR>\n";
	}
	else {
	  $error .= "Could not change function of $1 to $newfunc<BR>\n";
	}
      }
    }
  }

  my $hiddenvalues = {};
  
  $hiddenvalues->{ 'actionhidden' } = 'none'; 
  $hiddenvalues->{ 'fr' } = $funcrole; 
  $hiddenvalues->{ 'subsystem' } = $name;
  $hiddenvalues->{ 'Sequence' } = 'Protein Sequence';

  my $pegs = $self->pegs_for_fr( $fr, $subsystem, $showminus );

  # create table headers
  my $table_columns = [ '',
			{ name => 'CDS', filter => 1, sortable => 1 },
			{ name => 'Domain', filter => 1, operator => 'combobox', sortable => 1 },
			{ name => 'Organism', filter => 1, sortable => 1 },
			{ name => 'Current Function', filter => 1, sortable => 1 },
			{ name => 'Length (AA)', filter => 1, sortable => 1 },
			{ name => 'Other Subsystems', filter => 1, sortable => 1 },
			{ name => 'FIGFAMs', filter => 1, sortable => 1 }, 
		      ];
  
  # create table from parsed data
  my $table = $application->component( 'PegTable' );
  $table->columns( $table_columns );
  $table->data( $pegs );
  $table->show_top_browse( 1 );
  $table->show_export_button( { strip_html => 1,
				hide_invisible_columns => 1,
			        title      => 'Export plain data to Excel' } );
#  $table->items_per_page( 20 );
#  $table->show_select_items_per_page( 1 );


  # spreadsheetbuttons #
  my $buttons = $self->get_spreadsheet_buttons( $name );
  my $functionalrole = $subsystem->get_role_from_abbr( $funcrole );

  my $content = "<H1>Genes for column $fr</H1>";

  if ( defined( $comment ) && $comment ne '' ) {
    my $info_component = $application->component( 'CommentInfo' );

    $info_component->content( $comment );
    $info_component->default( 0 );
    $content .= $info_component->output();
  }    

  $content .= "<H2>Functional Role: $functionalrole</H2>";
  $content .= "<H2>Subsystem:       $ssname</H2>";

  # start form #
  $content .= $self->start_form( 'form', $hiddenvalues );
  $content .= $buttons;
  $content .= $table->output();
  $content .= $buttons;
  $content .= $self->end_form();

  ###############################
  # Display errors and comments #
  ###############################
 
  if ( defined( $error ) && $error ne '' ) {
    $self->application->add_message( 'warning', $error );
  }

  return $content;
}


sub pegs_for_fr {
    my( $self, $role, $subsystem, $show_minus1 ) = @_;

    # FigFams
    my $figfamsObject = new FFs($self->{fig}->get_figfams_data(), $self->{ 'fig' } );

    my $functionalrole = $subsystem->get_role_from_abbr( $role );

    my @cdss = ();
    foreach my $genome ( $subsystem->get_genomes )
    {
	my $vcode_value = $subsystem->get_variant_code( $subsystem->get_genome_index( $genome ) );
	if ( $show_minus1 || ( $vcode_value ne "-1" ) )
	{
	  foreach my $c ( $subsystem->get_pegs_from_cell( $genome,$role ) ) {
	    my $org = $self->{ 'fig' }->org_of( $c );
	    my $domain = $self->{ 'fig' }->genome_domain( $genome );
	    my $length = $self->{ 'fig' }->translation_length( $c );
	    my $func = $self->{ 'fig' }->function_of( $c );
	    my $sss = join "; ", map { $_->[0] } $self->{ 'fig' }->subsystems_for_peg( $c );

	    my $peg_link = $self->fid_link( $c );
	    $peg_link = "<A HREF='$peg_link' target=_blank>$c</A>";

	    my @fams = $figfamsObject->families_containing_peg( $c );
	    my @famlinks;
	    foreach my $f ( @fams ) {
	      push @famlinks, "<a href='seedviewer.cgi?page=FigFamViewer&figfam=$f' target='_blank'>$f</a>";
	    }

	    if ( $self->{ 'can_alter' } ) {
	      my $cds_checkbox = $self->{ 'cgi' }->checkbox( -name     => 'cds_checkbox',
							     -id       => "cds_checkbox_$c",
							     -value    => "cds_checkbox_$c",
							     -label    => '',
							     -checked  => 0,
							     -override => 1,
							   );
	      my $index = index( $func, $functionalrole );
	      if ( $index > -1 ) {
		push( @cdss, [ $cds_checkbox, $peg_link, $domain, $org, $func, $length, $sss, join( ', ', @famlinks ) ] );
	      }
	      else {
		push( @cdss, [ $cds_checkbox, $peg_link, $domain, $org, { 'data' => $func,
									  'highlight' => '#ff8888' }, 
			       $length, $sss, join( ', ', @famlinks ) ] );
	      }
	    }
	    else {
	      push( @cdss, [ $peg_link, $domain, $org, $func, $length, $sss, , join( ', ', @famlinks ) ] );
	    }
	  }
	}
    }
    return \@cdss;
}


###########################
# Buttons under the table #
###########################
sub get_spreadsheet_buttons {

  my ( $self, $name ) = @_;
  my $application = $self->application;

  my $buttons = "<DIV id='controlpanel'><H2>Actions</H2>\n";

  my $checkall    = "<INPUT TYPE=BUTTON name='CheckAll' value='Check All' onclick='checkAll( \"cds_checkbox\" )'>\n";
  my $checkfirst  = "<INPUT TYPE=BUTTON name='CheckFirst' value='Check First Half' onclick='checkFirst( \"cds_checkbox\" )'>\n";
  my $checksecond = "<INPUT TYPE=BUTTON name='CheckSecond' value='Check Second Half' onclick='checkSecond( \"cds_checkbox\" )'>\n";
  my $uncheckall  = "<INPUT TYPE=BUTTON name='UnCheckAll' value='Uncheck All' onclick='uncheckAll( \"cds_checkbox\" )'>\n";

  my $frtextfield = "<INPUT TYPE=TEXT NAME=FRTEXT SIZE=50>";
  my $querytextfield = "<INPUT TYPE=TEXT NAME=QUERYTEXT SIZE=50>";
  my $rptextfield = "<INPUT TYPE=TEXT NAME=RPTEXT SIZE=50>";

  my $renamebutton  = "<INPUT TYPE=BUTTON name='Rename' value='Change function of all checked pegs' onclick='if ( confirm( \"Do you really want to annotate the checked CDSs with the given function?\" ) ) { 
SubmitGenes( \"Rename\", 0 ); }''>\n";
  my $replacebutton  = "<INPUT TYPE=BUTTON name='Replace' value=\"Replace string in\nall checked pegs\" onclick='if ( confirm( \"Do you really want to replace the given string of the checked CDSs?\" ) ) { 
SubmitGenes( \"Replace\", 0 ); }''>\n";
  my $alignbutton = "<INPUT TYPE=BUTTON VALUE=\"Align Selected Sequences (Tcoffee)\" ID='Alignbutton' ONCLICK='AlignSeqs( \"".$application->url()."\" );'>";
  my $alignbuttonclustal = "<INPUT TYPE=BUTTON VALUE=\"Align Selected Sequences (Clustal)\" ID='AlignbuttonClustal' ONCLICK='AlignSeqs( \"".$application->url()."\", \"clustal\" );'><INPUT TYPE=HIDDEN ID='align_format' NAME='align_format' value='clustal'><INPUT TYPE=HIDDEN ID='tree_format' NAME='tree_format' value='normal'>";
  my $showsequencesbutton = "<INPUT TYPE=BUTTON VALUE=\"Show Selected Sequences\" ID='Showsequencesbutton' ONCLICK='ShowSeqs( \"".$application->url()."\" );'>";

  $buttons .= "<TABLE><TR><TD><B>Select:</B></TD><TD>$checkall</TD><TD>$checkfirst</TD><TD>$checksecond</TD><TD>$uncheckall</TD></TR></TABLE><BR>";
  if ( $self->{ 'can_alter' } ) {
    $buttons .= "<TABLE><TR><TD><B>Set peg function to:</B></TD><TD>$frtextfield</TD><TD>$renamebutton</TD></TR></TABLE><BR>";
    $buttons .= "<TABLE><TR><TD><B>Replace string: </B></TD><TD>$querytextfield</TD><TD rowspan=2>$replacebutton</TD></TR><TR><TD align=right><B>with: </B></TD><TD>$rptextfield</TD></TR></TABLE>";
  }
  $buttons .= "<TABLE><TR><TD><B>Sequences: </B></TD><TD>$showsequencesbutton</TD><TD>$alignbutton</TD><TD>$alignbuttonclustal</TD></TR></TABLE>";
  $buttons .= "</DIV>";

  return $buttons;
}

sub fid_link {
    my ( $self, $fid ) = @_;
    my $n;
    my $seeduser = $self->{ 'seeduser' };

    if ($fid =~ /^fig\|\d+\.\d+\.([a-zA-Z]+)\.(\d+)/) {
      if ( $1 eq "peg" ) {
	  $n = $2;
	}
      else {
	  $n = "$1.$2";
	}
    }

#    return "./protein.cgi?prot=$fid&user=$seeduser\&new_framework=0";
    return qq~./seedviewer.cgi?page=Annotation&feature=$fid&user=$seeduser~;
}
