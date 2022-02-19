package SubsystemEditor::WebPage::ShowIllustrations;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;
use WebComponent::WebGD;

use FIG;

use constant ROLE => ''; # 'index.cgi?action=ShowFunctionalRole&subsystem_name=<SUBSYSTEM>&role_abbr=<ROLE>';
use constant SUBSYSTEM => 'diagram.cgi?subsystem_name=<SUBSYSTEM>';
use constant MAX_WIDTH => 800;
use constant MAX_HEIGHT => 700;
use constant MIN_SCALE => 0.65;

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
  
  my $fig = new FIG;
  my $cgi = $self->application->cgi;
  
  my $name = $cgi->param( 'subsystem' );
  my $ssname = $name;
  $ssname =~ s/\_/ /g;

  my $esc_name = uri_escape($name);

  my $subsystem = new Subsystem( $name, $fig, 0 );

  # look if someone is logged in and can write the subsystem #
  my $can_alter = 0;
  my $user = $self->application->session->user;
  if ( $user && $user->has_right( $self->application, 'edit', 'subsystem', $name ) ) {
    $can_alter = 1;
  }

  ######################
  # Construct the menu #
  ######################

  my $menu = $self->application->menu();

  # Build nice tab menu here
  $menu->add_category( 'Subsystem Info', "SubsysEditor.cgi?page=ShowSubsystem&subsystem=$esc_name" );
  $menu->add_category( 'Functional Roles', "SubsysEditor.cgi?page=ShowFunctionalRoles&subsystem=$esc_name" );
  $menu->add_category( 'Subsets', "SubsysEditor.cgi?page=ShowSubsets&subsystem=$esc_name" );
  $menu->add_category( 'Diagrams and Illustrations' );
  $menu->add_entry( 'Diagrams and Illustrations', 'Diagram', "SubsysEditor.cgi?page=ShowDiagram&subsystem=$esc_name" );
  $menu->add_entry( 'Diagrams and Illustrations', 'Illustrations', "SubsysEditor.cgi?page=ShowIllustrations&subsystem=$esc_name" );
  $menu->add_category( 'Spreadsheet', "SubsysEditor.cgi?page=ShowSpreadsheet&subsystem=$esc_name" );
  $menu->add_category( 'Show Check', "SubsysEditor.cgi?page=ShowCheck&subsystem=$esc_name" );
  $menu->add_category( 'Show Connections', "SubsysEditor.cgi?page=ShowTree&subsystem=$esc_name" );

  my $error = '';
  my $comment = '';

  #########
  # TASKS #
  #########

  if ( defined( $cgi->param( 'DELETEBUTTONPRESSED' ) ) && $cgi->param( 'DELETEBUTTONPRESSED' ) == 1 ) {
    my $diagramid = $cgi->param( 'DIAGRAMID' );
    &delete_illustration( $subsystem, $diagramid );
    $cgi->delete( 'diagram' );
    $cgi->delete( 'DIAGRAMID' );
    $cgi->delete( 'diagram_selectbox' );
  }

  ##############################
  # Construct the page content #
  ##############################

  my $content = "<H1>Subsystem Illustrations: $ssname</H1>";
  $content .= "<P>Illustrations are general diagrams related to the subsystem that cannot be colored.</P>";

  my $diagram = $self->get_Diagram( $fig, $cgi, $can_alter );

  $content .= $diagram;


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


sub get_data {

  my ( $fig, $subsystem_name ) = @_;
  my $subsystem = $fig->get_subsystem( $subsystem_name );

  my $default_diagram;
  my $newDiagrams;

  foreach my $d ( $subsystem->get_diagrams ) {
    my ( $id, $name ) = @$d;
    unless ( $subsystem->is_new_diagram( $id ) ) {
      $newDiagrams->{ $id }->{ 'name' } = $name;
      if ( !defined( $default_diagram ) ) {
	$default_diagram = $id;
      }
    }
  }
  
  return ( $subsystem, $newDiagrams, $default_diagram );
}

sub get_Diagram {
    my ( $self, $fig, $cgi, $can_alter ) = @_;

    # get the subsystem
    unless ( $cgi->param( 'subsystem' ) ) {
	return '<p>CGI Parameter missing.</p>';
    }
    my $subsystem_name = $cgi->param( 'subsystem' ) || '';
    my $subsystem_pretty = $subsystem_name;
    $subsystem_pretty =~ s/_/ /g;
    my ( $subsystem, $newDiagrams, $defaultDiagram ) = get_data( $fig, $subsystem_name );

    my $esc_name = uri_escape($subsystem_name);

    # check subsystem
    unless ( $subsystem ) {
      return "<p>Unable to find a subsystem called '$subsystem_name'.</p>";
    }

    #####################################
    # get values for attribute coloring #
    #####################################

    my $color_by_attribute = 0;
    my $attribute = $cgi->param( 'attribute_selectbox' );
  

    # if diagram.cgi is called without the CGI param diagram (the diagram id)
    # it will try to load the first 'new' diagram from the subsystem and
    # print out an error message if there is no 'new' diagram
    my $diagram_id  = $cgi->param( 'diagram' ) || $cgi->param( 'diagram_selectbox' ) || '';

    if ( defined( $cgi->param( 'Show this illustration' ) ) ) {
      $diagram_id = $cgi->param( 'diagram_selectbox' );
    }

    unless ( $diagram_id ) {
      $diagram_id = $defaultDiagram;
      $cgi->param( 'diagram_selectbox', $diagram_id );
    }

    # check diagram id
    my $errortext = '';

    if ( !( $diagram_id ) ) {
      $errortext .= "<p><em>Unable to find a diagram for this subsystem.</em><p>";
    }

    # initialise a status string (log)
    my $status = '';
    
    # generate the content
    my $content = $errortext;

    # start form #
    $content .= $self->start_form( 'diagram_select_genome' ); 
    $content .= "<TABLE><TR><TD>";

    my $choose = build_show_other_diagram( $fig, $cgi, $subsystem, $newDiagrams, $diagram_id );

    my $scale = 1;

    $content .= "<DIV id='controlpanel'>$choose</DIV></TD><TR><TR><TD>";

    if ( $diagram_id ) {

      # fetch the diagram
      my $diagram_dir = $subsystem->{dir}."/diagrams/$diagram_id/";

      if ( !( -d $diagram_dir ) ) {
	$errortext .= "<P>The given diagram can not be found</P>";
      }

      my $d = $diagram_dir;
      if ( -f $diagram_dir.'diagram.png' ) {
	$d = $diagram_dir.'diagram.png';
      }
      elsif ( -f $diagram_dir.'diagram.jpg' ) {
	$d = $diagram_dir.'diagram.jpg';
      }
      elsif ( -f $diagram_dir.'diagram.gif' ) {
	$d = $diagram_dir.'diagram.gif';
      }

      # print diagram
      my $image = WebGD->new( $d );


      my ( $width, $height ) = ( $image->getBounds() );

      unless ( $cgi->param( 'dont_scale' ) ) {
	( $scale, $width, $height ) = calculate_scale( $width, $height );
      }

      $content .= "<DIV><IMG SRC=\"".$image->image_src()."\" width=$width height=$height></DIV>";

      # add an info line about diagram scaling
      my $scaling_info;
      if ( $scale == 1 ) {
	$scaling_info .= '<p><em>This diagram is not scaled.</em></p>';
      }
      else {
	$scaling_info .= '<p><em>This diagram has been scaled to '.$scale.'%. ';
	$scaling_info .= "(<a href='".$self->application->url()."?page=ShowIllustrations&subsystem=$esc_name&diagram=$diagram_id&dont_scale=1'>".
	  "view in original size</a>)";
	$scaling_info .= '</em></p>';
      }
      if ( $cgi->param( 'dont_scale' ) ) {
	$scaling_info .= '<p><em>You have switched off scaling this diagram down. ';
	$scaling_info .= "(<a href='".$self->application->url()."?page=ShowIllustrations&subsystem=$esc_name&diagram=$diagram_id'>".
	  "Allow scaling</a>)";
	$scaling_info .= '</em></p>';
      }	

      $content .= "</TD></TR><TR><TD>$scaling_info</TD></TR>";
    }

    $content .= "<TR><TD><DIV id='controlpanel'>$choose";

    # upload diagram only if can_alter #
    if ( $can_alter ) {
      my $upload = $self->build_upload_diagram( $fig, $esc_name );
      $content .= "$upload";
      
      my $delete = '';
      if ( defined( $diagram_id ) ) {
	$delete = $self->build_delete_diagram( $fig, $esc_name, $diagram_id );
	$content .= "$delete";
      }
    }

    $content .= "</DIV></TD><TR></TABLE>";

    # hiddens for subsystem, diagram, scale #
    $content .= $cgi->hidden( -name  => 'subsystem',
			      -value => $esc_name );	
    $content .= $cgi->hidden( -name  => 'diagram',
			      -value => $diagram_id );
    
    $content .= $cgi->hidden( -name  => 'dont_scale', -value => 1 ) 
      if ( $cgi->param( 'dont_scale' ) );
    
    $content .= $self->end_form();

    return $content;
  }

#######################################
# build the little show other diagram #
#######################################
sub build_show_other_diagram {

  my ( $fig, $cgi, $subsystem, $diagrams, $default ) = @_;
  
  my $default_num;

  my @ids = sort keys %$diagrams;
  my %names;
  my $counter = 0;
  foreach ( @ids ) {
    if ( $_ eq $default ) {
      $default_num = $counter;
    }
    $names{ $_ } = $diagrams->{ $_ }->{ 'name' };
    $counter++;
  }

  my $diagramchoose = "<H2>Choose other illustration</H2>\n";
  if ( scalar( @ids ) == 1 ) {
    $diagramchoose .= "<P>There is one illustration for this subsystem.</P>";
  }
  else {
    $diagramchoose .= "<P>There are ".scalar( @ids )." illustrations for this subsystem.</P>";
  }
  $diagramchoose .= $cgi->popup_menu( -name    => 'diagram_selectbox',
 				      -values  => \@ids,
 				      -default => $default_num,
 				      -labels  => \%names,
				      -maxlength  => 150,
 				    );

  $diagramchoose .= $cgi->submit( -name => 'Show this illustration' );

  return $diagramchoose;
}


###################################
# build the little upload diagram #
###################################
sub build_upload_diagram {

  my ( $self, $fig, $subsystem_name ) = @_;
  
  my $diagramupload = "<H2>Upload new illustration</H2>\n";
  $diagramupload .= "<A HREF='".$self->application->url()."?page=UploadDiagram&subsystem=$subsystem_name&illustration=1' target='_blank'>Upload a new illustration or change an existing one for this subsystem</A>";

  return $diagramupload;

}

###################################
# build the little delete diagram #
###################################
sub build_delete_diagram {

  my ( $self, $fig, $subsystem, $diagramid ) = @_;
  
  my $diagramdelete = "<H2>Delete currently shown illustration</H2>\n";

  my $deletebutton = "<INPUT TYPE=HIDDEN NAME='DIAGRAMID' ID='DIAGRAMID' VALUE='$diagramid'><INPUT TYPE=HIDDEN NAME='DELETEBUTTONPRESSED' ID='DELETEBUTTONPRESSED' VALUE=0><INPUT TYPE=BUTTON VALUE='Delete Illustration' NAME='DELETEDIAGRAMBUTTON' ID='DELETEDIAGRAMBUTTON' ONCLICK='if ( confirm( \"Do you really want to illustration the diagram $diagramid?\" ) ) { 
 document.getElementById( \"DELETEBUTTONPRESSED\" ).value = 1;
 document.getElementById( \"diagram_select_genome\" ).submit(); }'>";
  
  $diagramdelete .= $deletebutton;

}

sub calculate_scale {
  my ( $width, $height ) = @_;
 
  my $scale = 1; 
  if ( $width > MAX_WIDTH ) {
    $scale = MAX_WIDTH / $width;
  }
  if ( $height > MAX_HEIGHT and 
      (( MAX_HEIGHT / $height) < $scale) ) {
    $scale = MAX_HEIGHT / $height;
  }

  $scale = $scale < MIN_SCALE ? MIN_SCALE : $scale ;

  return ( $scale, $scale * $width, $scale * $height );
}

sub delete_illustration {

  my ( $subsystem, $id ) = @_;
  
  $subsystem->delete_diagram( $id );
}
