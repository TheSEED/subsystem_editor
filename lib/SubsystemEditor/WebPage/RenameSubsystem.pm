package SubsystemEditor::WebPage::RenameSubsystem;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;
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
  
  $self->{ 'fig' } = new FIG;
  $self->{ 'cgi' } = $self->application->cgi;
  my $application = $self->application();
  $self->application->show_login_user_info(1);

  # subsystem name and 'nice name' #
  my $name = $self->{ 'cgi' }->param( 'subsystem' );

  if ( $name =~ /subsystem\_checkbox\_(.*)/ ) {
    $name = $1;
  }
  $name = uri_unescape( $name );

  my $ssname = $name;
  $ssname =~ s/\_/ /g;

  # look if someone is logged in and can write the subsystem #
  my $can_alter = 0;
  my $user = $self->application->session->user;
  if ( $user ) {
    if ( $user->has_right( $self->application, 'edit', 'subsystem', $name ) ) {
      $can_alter = 1;
    }
  }

  my $dbmaster = $self->application->dbmaster;
  my $ppoapplication = $self->application->backend;

  # get a seeduser #
  my $seeduser = '';
  if ( defined( $user ) && ref( $user ) ) {
    my $preferences = $dbmaster->Preferences->get_objects( { user => $user,
							     name => 'SeedUser',
							     application => $ppoapplication } );
    if ( defined( $preferences->[0] ) ) {
      $seeduser = $preferences->[0]->value();
    }
    $self->{ 'fig' }->set_user( $seeduser );
  }
  else {
    $self->application->add_message( 'warning', "No user defined, please log in first\n" );
    return "<H1>Manage my subsystems</H1>";
  }

  my ( $comment, $error ) = ( "" );


  #########
  # TASKS #
  #########

  my $esc_name = uri_escape($name);
  
  if ( $self->{ 'cgi' }->param( 'GORENAME' ) && defined( $self->{ 'cgi' }->param( 'newssname' ) ) && $self->{ 'cgi' }->param( 'newssname' ) ne '' ) {
    my $newssname = $self->{ 'cgi' }->param( 'newssname' );
    
    my $subsystem = new Subsystem( $newssname, $self->{ 'fig' }, 0 );
    
    if ( defined( $subsystem ) ) {
      $self->application->add_message( 'warning', "There is already a subsystem named $ssname<BR>" );
    }
    else {
      my $usnewssname = $newssname;
      $newssname =~ s/ /\_/g;
      
      # first rename the ssname on disk and in database
      $self->{ 'fig' }->rename_subsystem( $name, $newssname );
      
      # Now we have to check if the rename has really happened
      my $subsystemNEW = new Subsystem( $newssname, $self->{ 'fig' }, 0 );
      if ( defined( $subsystemNEW ) ) {
	$comment .= "The subsystem named $newssname is now present<BR>";
      }
      else {
	$self->application->add_message( 'warning', "The subsystem named $newssname could not be build<BR>" );
      }
      # Now we have to check if the rename has really happened
      my $subsystemOLD = new Subsystem( $ssname, $self->{ 'fig' }, 0 );
      if ( !defined( $subsystemOLD ) ) {
	$comment .= "The subsystem named $ssname does not exist (any more)<BR>";
      }
      
      # get old right
      my $oldrights = $dbmaster->Rights->get_objects({ scope       => $user->get_user_scope,
						       data_type   => 'subsystem',
						       data_id     => $name,
						       name        => 'edit'
						     });

      if ( defined( $oldrights->[0] ) ) {
	$oldrights->[0]->delete();
      }

      # get old right
      my $newrights = $dbmaster->Rights->get_objects({ scope       => $user->get_user_scope,
						       data_type   => 'subsystem',
						       data_id     => $newssname,
						       name        => 'edit'
						     });
      if ( scalar( @$newrights ) == 0 ) {
	# now move edit rights, curator etc to the new name
	my $right = $dbmaster->Rights->create( { name => 'edit',
						 scope => $user->get_user_scope,
						 data_type => 'subsystem',
						 data_id => $newssname,
						 granted => 1,
						 delegated => 0 } );
      }
       

      my @attrs = $self->{ 'fig' }->get_attributes( 'Subsystem:'.$esc_name );

       foreach my $att ( @attrs ) {
	 my ( $ss, $key, $value ) = @$att;
	 $self->{ 'fig' }->delete_matching_attributes( "Subsystem:$esc_name", "SUBSYSTEM_PUBMED_RELEVANT", $value );
	 my $esc_newssname = uri_escape($newssname);
	 $self->{ 'fig' }->add_attribute( "Subsystem:$esc_newssname", "SUBSYSTEM_PUBMED_RELEVANT", $value );
       }
       
       $comment .= "Renamed $ssname to $newssname!\n";
       $ssname = $usnewssname;
     }
   }

  my $content = "<H1>Rename subsystem $ssname</H1>";
  $content .= $self->start_form( 'manage' );

  if ( $can_alter ) {
    $content .= "<TABLE><TR><TD>Rename To:</TD><TD><INPUT TYPE=TEXT NAME=\"newssname\" SIZE=70></TD></TR></TABLE>";
    $content .= "<INPUT TYPE=SUBMIT ID='GORENAME' NAME='GORENAME' VALUE='Rename Now !'>";
  }
  else {
    $error .= "You do not have the rights to rename subsystem $ssname. Are you logged in? <BR>";
  }
  
  $content .= "<INPUT TYPE=HIDDEN NAME='subsystem' ID='subsystem' VALUE='$esc_name'>";

  $content .= $self->end_form();

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


sub supported_rights {
  
return [ [ 'login', '*', '*' ] ];

}
