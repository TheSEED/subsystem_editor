package SubsystemEditor::WebPage::UploadDiagram;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;

use Diagram;

use FIG;

use base qw( WebPage );

1;

##################################################
# Method for registering components etc. for the #
# application                                    #
##################################################
sub init {
  my ( $self ) = @_;
}

sub require_javascript {

  return [ './Html/showfunctionalroles.js' ];

}

##############################################
# Website content is returned by this method #
##############################################
sub output {
  my ( $self ) = @_;

  my $can_alter = 1;
  
  my $fig = new FIG;
  my $cgi = $self->application->cgi;
  
  my $name = $cgi->param( 'subsystem' );
  my $ssname = $name;
  $ssname =~ s/\_/ /g;
  
  my $esc_name = uri_escape($name);

  my $subsystem = new Subsystem( $name, $fig, 0 );

  if ( !defined( $name ) ) {
    my $nocontent = "<H1>Upload / Change Diagram for: - </H1>";
    $nocontent .= "No subsystem given!\n";
    return $nocontent;
  }

  my $illustration = $cgi->param( 'illustration' );

  ######################
  # Construct the menu #
  ######################

  my $menu = $self->application->menu();

  # Build nice tab menu here
  $menu->add_category( 'Subsystem Info', "SubsysEditor.cgi?page=ShowSubsystem&subsystem=$esc_name" );
  $menu->add_category( 'Functional Roles', "SubsysEditor.cgi?page=ShowFunctionalRoles&subsystem=$esc_name" );
  $menu->add_category( 'Diagrams and Illustrations' );
  $menu->add_entry( 'Diagrams and Illustrations', 'Diagram', "SubsysEditor.cgi?page=ShowDiagram&subsystem=$esc_name" );
  $menu->add_entry( 'Diagrams and Illustrations', 'Illustrations', "SubsysEditor.cgi?page=ShowIllustrations&subsystem=$esc_name" );
  $menu->add_category( 'Spreadsheet', "SubsysEditor.cgi?page=ShowSpreadsheet&subsystem=$esc_name" );
  $menu->add_category( 'Show Check', "SubsysEditor.cgi?page=ShowCheck&subsystem=$esc_name" );
  $menu->add_category( 'Show Connections', "SubsysEditor.cgi?page=ShowTree&subsystem=$esc_name" );
 
  my $error = '';
  my $comment = '';

  ##############################
  # Construct the page content #
  ##############################

  my $content = "<H1>Upload / Change Diagram for:  $ssname</H1>";

  if ( $cgi->param('Upload') ) {
    if ( $cgi->param('subsystem' ) ) {
      if ( $illustration ) {
	if ( ( $cgi->param('change_diagram') eq 'new' and $cgi->param('diagram_name') and 
	       $cgi->param('diagram_image') ) or
	     ( $cgi->param('change_diagram') ne 'new' and 
	       ( $cgi->param('diagram_name') or $cgi->param('diagram_image') ) ) ) { 
	  ( $comment, $error ) = do_Upload( $fig, $cgi, $illustration );
	}
	else {
	  $error = "Not all required information given<BR>\n";
	}
      }
      else {
	if ( ( $cgi->param('change_diagram') eq 'new' and $cgi->param('diagram_name') and 
	       $cgi->param('diagram_image') and $cgi->param('diagram_map') ) or
	     ( $cgi->param('change_diagram') ne 'new' and 
	       ( $cgi->param('diagram_name') or $cgi->param('diagram_image') or 
		 $cgi->param('diagram_map') ) ) ) { 
	  ( $comment, $error ) = do_Upload( $fig, $cgi );
	}
	else {
	  $error = "Not all required information given<BR>\n";
	}
      }
    }
    else {
      $error = "No subsystem given\n";
    }
  }

    $content .= $self->show_Upload( $fig, $cgi, $illustration );



  ###############################
  # Display errors and comments #
  ###############################
 
  if ( defined( $error ) && $error ne '' ) {
    $self->application->add_message( 'warning', $error );
  }
  if ( defined( $comment ) && $comment ne '' ) {
    $self->application->add_message( 'info', $comment );
  }

  return $content;
}


sub show_Upload {
    my ( $self, $fig, $cgi, $illustration ) = @_;

    my $content .= $self->start_form();
    $content .= '<table>';

    my ( $new_diagrams, $labels ) = getDiagrams( $fig, $cgi );
    
    my $subsystem_name = $cgi->param('subsystem');
    $subsystem_name =~ s/_/ /g;
    $content .= '<tr><th>Subsystem: </th><td>'.$subsystem_name.
      $cgi->hidden(-name=>'subsystem', -value=>$cgi->param('subsystem'));
    $content .= $cgi->hidden( -name => 'illustration', -value => $cgi->param( 'Illustration' ) ).'</td></tr>';
    $content .= '<tr><th>Update existing? </th><td>'.
      $cgi->popup_menu(-name=>'change_diagram', -values=>$new_diagrams, -labels=>$labels, -default=>'new',).'</td></tr>';
    $content .= '<tr><th>Diagram Name: </th><td>'.
      $cgi->textfield(-name=>'diagram_name', -size=>55).'</td></tr>';
    $content .= '<tr><th>Image File: </th><td>'.
      $cgi->filefield(-name=>'diagram_image', -size=>55).'</td></tr>';
    if ( !$illustration ) {
      $content .= '<tr><th>Html Map File: </th><td>';
      $content .= $cgi->filefield(-name=>'diagram_map', -size=>55).'</td></tr>';
    }
    
    $content .= '<tr><td colspan="2">'.$cgi->submit(-name=>'Upload'). '</td></tr>';
    $content .= $self->end_form();
    $content .= '</table>';

    return $content;
}


sub do_Upload {
    my ( $fig, $cgi, $illustration ) = @_;

    my $error = '';
    my $comment = '';


    my $subsystem = $fig->get_subsystem( $cgi->param( 'subsystem' ) );
    my $id = ( $cgi->param( 'change_diagram' ) ) ? $cgi->param( 'change_diagram' ) : undef;
    
    
    if ($cgi->param('change_diagram') eq 'new' ) {

      if ( $illustration ) {

	$id = $subsystem->create_new_diagram($cgi->param( 'diagram_image' ), 
					     undef,
					     $cgi->param( 'diagram_name' ) );
	$comment .= 'Uploaded new illustration ' . $cgi->param( 'diagram_name' ) . '<BR>';
      }
      else {
	$id = $subsystem->create_new_diagram($cgi->param( 'diagram_image' ), 
					     $cgi->param( 'diagram_map' ),
					     $cgi->param( 'diagram_name' ) );
	$comment .= 'Uploaded new diagram ' . $cgi->param( 'diagram_name' ) . '<BR>';
      }
    }
    else {
      if ( $illustration ) {
	if ($cgi->param('diagram_name')) {
	  $subsystem->rename_diagram($cgi->param('change_diagram'), $cgi->param('diagram_name'));
	  $comment .= '<p><em>Changed diagram name (id: '.$cgi->param('change_diagram').') to '.
	    $cgi->param('diagram_name').'</em></p>';
	}
	
	if ($cgi->param('diagram_image')) {
	  $subsystem->upload_new_image($cgi->param('change_diagram'), $cgi->param('diagram_image'));
	  $comment .= '<p><em>New image uploaded for diagram (id: '.$cgi->param('change_diagram').').</em></p>';
	}
      }
      else {
	if ($cgi->param('diagram_name')) {
	  $subsystem->rename_diagram($cgi->param('change_diagram'), $cgi->param('diagram_name'));
	  $comment .= '<p><em>Changed diagram name (id: '.$cgi->param('change_diagram').') to '.
	    $cgi->param('diagram_name').'</em></p>';
	}
	
	if ($cgi->param('diagram_image')) {
	  $subsystem->upload_new_image($cgi->param('change_diagram'), $cgi->param('diagram_image'));
	  $comment .= '<p><em>New image uploaded for diagram (id: '.$cgi->param('change_diagram').').</em></p>';
	}
	
	if ($cgi->param('diagram_map')) {
	  $subsystem->upload_new_html($cgi->param('change_diagram'), $cgi->param('diagram_map'));
	  $comment .= '<p><em>New html map uploaded for diagram (id: '.$cgi->param('change_diagram').').</em></p>';
	}
      }
    }

    unless ( $comment ) {
	$error .= '<p><em>Nothing was done, try giving at least one parameter!</em></p>';
    }

#    if ( defined $id ) {
#	$comment .= '<a href="diagram.cgi?subsystem_name='.$cgi->param('subsystem').
#	    '&diagram='.$id.'" target="_new_diagram">[ view this subsystem diagram ]</a><BR>';
#    }
#    $comment .= '<p><em><a href="diagram_upload.cgi?subsystem='.$cgi->param('subsystem').'">[ go back to this subsystem upload ]</a></em></p>';
#    $comment .= '<p><em><a href="diagram_upload.cgi">[ start over ]</a></em></p>';
    
    return ( $comment, $error );

}


###############
# data method #
###############
sub getDiagrams {
  my ( $fig, $cgi ) = @_;

  # get existing 'new' diagrams
  my $subsystem = $fig->get_subsystem( $cgi->param( 'subsystem' ) );
  my @diagrams = $subsystem->get_diagrams(); # this is a @@: [ ($id, $name, $link) ]
  my $labels = { 'new' => 'new' };
  my $new_diagrams = [ 'new' ];
  for my $entry ( @diagrams ) {
    my ( $id, $name, $link ) = @$entry;
    if ( $subsystem->is_new_diagram( $id ) ) {
      push @$new_diagrams, $id;
      $labels->{ $id } = $name;
    }
  }
  
  return ( $new_diagrams, $labels );
}
