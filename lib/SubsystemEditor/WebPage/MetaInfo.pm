package SubsystemEditor::WebPage::MetaInfo;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;
use DBMaster;

use FIG;

use MIME::Base64;
use Data::Dumper;
use File::Spec;
use GenomeLists;
use MetaSubsystem;
use base qw( WebPage );

1;


##############################################################
# Method for registering components etc. for the application #
##############################################################
sub init {
  my ( $self ) = @_;

  $self->application->register_component( 'Info', 'CommentInfo');

  return 1;
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
  my $name = $self->{ 'cgi' }->param( 'metasubsystem' );
  my $ssname = $name;

  my $esc_name = uri_escape( $name );

  $ssname =~ s/\_/ /g;

  # look if someone is logged in and can write the subsystem #
  $self->{ 'can_alter' } = 0;
  my $user = $self->application->session->user;

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
  }

  $self->{ 'metasubsystem' } = new MetaSubsystem( $name, $self->{ 'fig' }, 0 );
  if ( !defined( $self->{ 'metasubsystem' } ) ) {
    my $content = '<H1>Meta Subsystem Info</H1>';
    $content .= "Subsystem $ssname does not exist!";
    return $content;
  }

  if ( $user ) {
    if ( $user->has_right( $self->application, 'edit', 'metasubsystem', $name ) ) {
      $self->{ 'can_alter' } = 1;
      $self->{ 'fig' }->set_user( $seeduser );
    }
    else {
      # we might have the problem that the user has not yet got the right for editing the
      # subsystem due to that it was created in the old seed or what do I know where.
      my $curatorOfSS = $self->{ 'metasubsystem' }->get_curator();

      my $su = lc( $seeduser );
      my $cu = lc( $curatorOfSS );
      if ( $su eq $cu ) {
	# now set the rights... 
	my $right = $dbmaster->Rights->create( { name => 'edit',
						 scope => $user->get_user_scope,
						 data_type => 'metasubsystem',
						 data_id => $name,
						 granted => 1,
						 delegated => 0 } );
	if ( $right ) {
	  $self->{ 'can_alter' } = 1;
	  $self->{ 'fig' }->set_user( $seeduser );
	}
      }
    }
  }

  my $hiddenvalues = {};
  my $build_subsets_string = '';

  my ( $error, $comment ) = ( "", "" );

  #########
  # TASKS #
  #########

  if ( defined( $self->{ 'cgi' }->param( 'SUBMIT' ) ) ) {

    # set description and notes
    my $descrp = $self->{ 'cgi' }->param( 'SSDESC' );
    chomp $descrp;
    $descrp .= "\n";
    $self->{ 'metasubsystem' }->set_description( $descrp );
    # here we really edit the files in the subsystem directory #
    $self->{ 'metasubsystem' }->incr_version();
    $self->{ 'metasubsystem' }->write_metasubsystem();
  }

  ######################
  # Construct the menu #
  ######################

  my $menu = $self->application->menu();

  # Build nice tab menu here
  $menu->add_category( 'Meta Overview', "SubsysEditor.cgi?page=MetaOverview" );
  $menu->add_category( 'Info', "SubsysEditor.cgi?page=MetaInfo&metasubsystem=$esc_name" );
  $menu->add_category( 'Edit Subsets', "SubsysEditor.cgi?page=MetaSubsets&metasubsystem=$esc_name" );
  $menu->add_category( 'Add/Remove Subsystems', "SubsysEditor.cgi?page=MetaEditSubsystems&metasubsystem=$esc_name" );
  $menu->add_category( 'Spreadsheet', "SubsysEditor.cgi?page=MetaSpreadsheet&metasubsystem=$esc_name" );

  ##############################
  # Construct the page content #
  ##############################

  my $sscurator = $self->{ 'metasubsystem' }->get_curator();
  my $ssversion = $self->{ 'metasubsystem' }->load_version();
  my $t = $self->{ 'metasubsystem' }->get_last_updated();
  my $mod_time = &FIG::epoch_to_readable( $t );
  my $ssdesc = $self->{ 'metasubsystem' }->get_description();

  my $infotable = "<TABLE><TR><TH>Name:</TH><TD>$ssname</TD></TR>";
  $infotable .= "<TR><TH>Author:</TH><TD>$sscurator</TD></TR>";
  $infotable .= "<TR><TH>Version:</TH><TD>$ssversion</TD></TR>";
  $infotable .= "<TR><TH>Last Modified:</TH><TD>$mod_time</TD></TR>";

  if ( $self->{ 'can_alter' } ) {
    $infotable .= "<TR><TH>Description</TH><TD><TEXTAREA NAME='SSDESC' ROWS=15 STYLE='width: 772px;'>$ssdesc</TEXTAREA></TD></TR>";
    $infotable .= "<INPUT TYPE=SUBMIT VALUE='Save Changes' ID='SUBMIT' NAME='SUBMIT'>";
  }
  else {
    my $ssdesc_brs = $ssdesc;
    $ssdesc_brs =~ s/\n/<BR>/g;
    $ssdesc_brs =~ s/(\n\s)+/\n/g;
    $infotable .= "<TR><TH>Description</TH><TD>$ssdesc_brs</TD></TR>";
  }

  my $content = '<H1>Meta Subsystem Info</H1>';
  $content .= $self->start_form( 'form', { metasubsystem => $name } );

  $content .= $infotable;
  $content .= $self->end_form();

  return $content;
}
