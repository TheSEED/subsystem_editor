package SubsystemEditor::WebPage::ManageMetaSubsystems;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;
use FIG;
use MetaSubsystem;

use base qw( WebPage );

1;

##################################################
# Method for registering components etc. for the #
# application                                    #
##################################################
sub init {
  my ( $self ) = @_;

  $self->application->register_component( 'Table', 'retttable' );
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
  
  $self->{ 'fig' } = $self->application->data_handle( 'FIG' );
  $self->{ 'cgi' } = $self->application->cgi;

  $self->application->show_login_user_info(1);
  $self->{ 'alleditable' } = $self->{ 'cgi' }->param( 'alleditable' );

  # look if someone is logged in and can write the subsystem #
  $self->{ 'can_alter' } = 0;
  $self->{ 'user' } = $self->application->session->user;
  if ( $self->{ 'user' } ) {
    $self->{ 'can_alter' } = 1;
  }

  my $dbmaster = $self->application->dbmaster();
  my $ppoapplication = $self->application->backend();

  # get a seeduser #
  $self->{ 'seeduser' } = '';
  if ( defined( $self->{ 'user' } ) && ref( $self->{ 'user' } ) ) {
    my $preferences = $dbmaster->Preferences->get_objects( { user => $self->{ 'user' },
							     name => 'SeedUser',
							     application => $ppoapplication } );
    if ( defined( $preferences->[0] ) ) {
      $self->{ 'seeduser' } = $preferences->[0]->value();
    }
    $self->{ 'fig' }->set_user( $self->{ 'seeduser' } );
  }
  else {
    $self->application->add_message( 'warning', "No user defined, please log in first\n" );
    return "<H1>Manage my subsystems</H1>";
  }

  my ( $comment, $error ) = ( "" );


  #########
  # TASKS #
  #########

  
  if ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'DeleteMetaSubsystems' ) {
    my @sstodelete = $self->{ 'cgi' }->param( 'subsystem_checkbox' );
    foreach my $sstd ( @sstodelete ) {
      if ( $sstd =~ /subsystem\_checkbox\_(.*)/ ) {
	my $ss = $1;
	$comment = $self->remove_metasubsystem( $ss );
      }
    }
  }

  # spreadsheetbuttons #
  my $actionbuttons = $self->get_spreadsheet_buttons();
  
  my $hiddenvalues;
  $hiddenvalues->{ 'buttonpressed' } = 'none';
  $hiddenvalues->{ 'alleditable' } = $self->{ 'alleditable' };

  my $content = "<H1>Manage my metasubsystems</H1>";

  if ( defined( $comment ) && $comment ne '' ) {
    my $info_component = $self->application->component( 'CommentInfo' );

    $info_component->content( $comment );
    $info_component->default( 0 );
    $content .= $info_component->output();
  }    

  $content .= $self->start_form( 'manage', $hiddenvalues );

  my ( $sstable, $putcomment ) = $self->getMetaSubsystemTable();
  $comment .= $putcomment;

  $content .= $actionbuttons;
  $content .= $sstable;
  $content .= $actionbuttons;

  $content .= $self->end_form();

  ###############################
  # Display errors and comments #
  ###############################
 
  if ( defined( $error ) && $error ne '' ) {
    $self->application->add_message( 'warning', $error );
  }

  return $content;
}


####################################
# get the subsystem overview table #
####################################
sub getMetaSubsystemTable {
  
  my ( $self ) = @_;
  
  my $comment = '';

  my $showright = defined( $self->{ 'cgi' }->param( 'SHOWRIGHT' ) );
  my $showmine = defined( $self->{ 'cgi' }->param( 'SHOWMINE' ) );

  my $rettable;
  
  opendir( SSA, "$FIG_Config::data/MetaSubsystems" ) or die "Could not open $FIG_Config::data/MetaSubsystems";
  my @sss = readdir( SSA );
  
  my $retcolumns = [ '',
  		     { 'name' => 'Subsystem Name',
		       'width' => 300,
		       'sortable' => 1,
		       'filter'   => 1 },
		     { 'name' => 'Subsystem Curator' }	    
  		   ];
  
  my $retdata = [];
  foreach ( @sss ) {
    next if ( $_ =~ /^\./ );

    my $name = $_;

    my $esc_name = uri_escape($name);
    my $owner = MetaSubsystem::get_curator_from_metaname( $name );
    
    if ( $self->{ 'alleditable' } && $self->{ 'user' }->has_right( $self->application, 'edit', 'metasubsystem', $name )
       || $owner eq $self->{ 'seeduser' } ) {
      $self->{ 'can_alter' } = 1;
      $self->{ 'fig' }->set_user( $self->{ 'seeduser' } );
    }
    else {
      next;
    }


    if ( defined( $name ) && $name ne '' && $name ne ' ' ) {  

      my $ssname = $name;
      $ssname =~ s/\_/ /g;

      if ( $name =~ /'/ ) {
	$name =~ s/'/&#39/;
      }

      my $esc_name = uri_escape($name);

      my $subsysurl = "SubsysEditor.cgi?page=MetaSpreadsheet&metasubsystem=$esc_name";
      
      my $subsystem_checkbox = $self->{ 'cgi' }->checkbox( -name     => 'subsystem_checkbox',
							   -id       => "subsystem_checkbox_$esc_name",
							   -value    => "subsystem_checkbox_$esc_name",
							   -label    => '',
							   -checked  => 0,
							   -override => 1 );
      
      my $retrow = [ $subsystem_checkbox,
		    "<A HREF='$subsysurl'>$ssname</A>",
		     $owner ];
      push @$retdata, $retrow;
    }
  }
  
  my $rettableobject = $self->application->component( 'retttable' );
  $rettableobject->width( 900 );
  $rettableobject->data( $retdata );
  $rettableobject->columns( $retcolumns );
  $rettable = $rettableobject->output();
  
  return ( $rettable, $comment );
}

sub supported_rights {
  
return [ [ 'login', '*', '*' ] ];

}

#################################
# Buttons under the spreadsheet #
#################################
sub get_spreadsheet_buttons {

  my ( $self ) = @_;
  
  my $delete_button = "<INPUT TYPE=HIDDEN VALUE=0 NAME='DeleteSS' ID='DeleteSS'>";
  $delete_button .= "<INPUT TYPE=BUTTON VALUE='Delete selected metasubsystems' NAME='DeleteMetaSubsystems' ID='DeleteSubsystems' ONCLICK='if ( confirm( \"Do you really want to delete the selected metasubsystems?\" ) ) { 
 document.getElementById( \"DeleteSS\" ).value = 1;
SubmitManage( \"DeleteMetaSubsystems\", 0 ); }'>";
  
  my $spreadsheetbuttons = "<DIV id='controlpanel'><H2>Actions</H2>\n";
  if ( $self->{ 'can_alter' } ) {
    $spreadsheetbuttons .= "<TABLE><TR><TD$delete_button</TD></TR></TABLE><BR>";
  }
  $spreadsheetbuttons .= "</DIV>";
  return $spreadsheetbuttons;
}

#######################################
# Remove genomes from the spreadsheet #
#######################################
sub remove_metasubsystem {
  my( $self, $metasubsystem ) = @_;

  my $name = $metasubsystem;
  $name =~ s/\_/ /g;
  
#  my $cmd = "rm -rf '$FIG_Config::data/Subsystems/$subsystem'";
  $self->{ 'fig' }->verify_dir( "$FIG_Config::data/MetaSubsystemsBACKUP" );
  my $cmd = "mv '$FIG_Config::data/MetaSubsystems/$metasubsystem' '$FIG_Config::data/MetaSubsystemsBACKUP/$metasubsystem"."_".time."'";
  my $rc = system $cmd;
  
  my $comment = "Deleted metasubsystem $name<BR>\n";

  return $comment;
}
