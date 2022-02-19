package SubsystemEditor::WebPage::ChangeCuratorSubsystem;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;

use FIG;
use FIGV;
use UnvSubsys;
use MetaSubsystem;

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

  # needed objects #
  $self->{ 'fig' } = new FIG;
  my $application = $self->application();
  $self->{ 'cgi' } = $application->cgi;

  my $dbmaster = $self->application->dbmaster;
  my $ppoapplication = $self->application->backend;

  # subsystem name and 'nice name' #
  my $name = $self->{ 'cgi' }->param( 'subsystem' );
  my $ssname = $name;
  $ssname =~ s/\_/ /g;
  $self->{ 'subsystem' } = $name;

  # look if someone is logged in and can write the subsystem #
  $self->{ 'can_alter' } = 0;
  my $user = $self->application->session->user;

  if ( $user && $user->has_right( undef, 'edit', 'subsystem', $name ) ) {
    $self->{ 'can_alter' } = 1;
  }

  # get a seeduser #
  if ( defined( $user ) && ref( $user ) ) {
    my $preferences = $dbmaster->Preferences->get_objects( { user => $user,
							     name => 'SeedUser',
							     application => $ppoapplication } );
    if ( defined( $preferences->[0] ) ) {
      $self->{ 'seeduser' } = $preferences->[0]->value();
    }
  }
  $self->{ 'fig' }->set_user( $self->{ 'seeduser' } );

  ################
  # hiddenvalues #
  ################
  my $hiddenvalues;
  $hiddenvalues->{ 'subsystem' } = $name;

  ###################
  # Construct parts #
  ###################
  my ( $putcomment, $puterror );
  my ( $comment, $error );

  if ( !defined( $self->{ 'subsystem' } ) ) {
    $error .= "No subsystem given<BR>";
    $self->application->add_message( 'warning', $error );
    return "<H1>Change curator for the subsystem $ssname</H1>";
  }

  #########
  # TASKS #
  #########
  my $justreset = 0;
  my $who = $self->{ 'cgi' }->param( 'to' );
  if ( $who ) {
    if ( (-d "$FIG_Config::data/Subsystems/".$self->{ 'subsystem' } ) && ( $self->{ 'fig' }->subsystem_curator ne $who ) ) {
      if ( $self->{ 'fig' }->reset_subsystem_curator( $self->{ 'subsystem' }, $who ) ) {
	$comment .= "Reset curator of ". $self->{ 'subsystem' } . " to $who.<BR>";
	$justreset = 1;
      }
      else {
	$error .= "Failed to reset curator of ". $self->{ 'subsystem' } . " to $who.<BR>";
      }
    }
  }

  ###########
  # Content #
  ###########

  my $content = "<H1>Change curator for the subsystem $ssname</H1>";
 
  if ( $self->{ 'can_alter' } && !defined( $self->{ 'cgi' }->param( 'to' ) ) ) {
    $content .= $self->start_form( 'chownsubsystem', $hiddenvalues );
    $content .= "<TABLE><TR>";
    $content .= "<TD>New Owner: </TD><TD><INPUT TYPE=TEXT STYLE='width: 200px;' NAME='to' ID='to' VALUE=''></TD>";
    $content .= "</TR></TABLE>";
    $content .= "<INPUT TYPE=SUBMIT>";

    $content .= $self->end_form();
  }
  elsif ( $justreset ) {
    $content .= "<P>The new Curator of this subsystem is $who<BR>\n";
  }
  else {
    $content .= "<P><I>You are not logged in or you do not have the right to change the curator of this subsystem.</I></P>";
  }

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
