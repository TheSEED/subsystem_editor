package SubsystemEditor::WebPage::MetaOverview;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;
use Mail::Mailer;
use MetaSubsystem;

use FIG;

use base qw( WebPage );

1;

##################################################
# Method for registering components etc. for the #
# application                                    #
##################################################
sub init {
  my ( $self ) = @_;

  $self->application->register_component( 'Table', 'retttable' );
}

##############################################
# Website content is returned by this method #
##############################################
sub output {
  my ( $self ) = @_;
  
  my $fig = new FIG;
  my $cgi = $self->application->cgi;
  $self->application->show_login_user_info(1);

  # look if someone is logged in and can write the subsystem #
  my $can_alter = 0;
  my $user = $self->application->session->user;
  if ( $user ) {
    $can_alter = 1;
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
    $fig->set_user( $seeduser );
  }
  
  my $content = "<H2>MetaSubsystems Overview</H2>";
  $content .= $self->start_form();
  if ( $user ) {
#    $content .= "<INPUT TYPE=SUBMIT NAME='SHOWRIGHT' ID='SHOWRIGHT' VALUE='Show only Subsystems I can Edit'>";
#    $content .= "<INPUT TYPE=SUBMIT NAME='SHOWMINE' ID='SHOWMINE' VALUE='Show only my Subsystems'>";
    $content .= "<INPUT TYPE=BUTTON NAME='NEWSUBSYS' ID='NEWSUBSYS' VALUE='Create new metasubsystem' onclick=\" window.open( '?page=NewMetaSubsystem' )\">";
    $content .= "<INPUT TYPE=BUTTON NAME='MANAGESUBSYS' ID='MANAGESUBSYS' VALUE='Manage my metasubsystems' onclick=\" window.open( '?page=ManageMetaSubsystems' )\">";
  }
  $content .= $self->end_form();

  my ( $sstable, $comment ) = getMetaSubsystemTable( $self, $fig, $can_alter, $user, $seeduser );
  
  $content .= $sstable;

  return $content;
}


####################################
# get the subsystem overview table #
####################################
sub getMetaSubsystemTable {
  
  my ( $self, $fig, $can_alter, $user, $seeduser ) = @_;
  
  my $cgi = $self->application->cgi;
  my $comment = '';

  my $showright = defined( $cgi->param( 'SHOWRIGHT' ) );
  my $showmine = defined( $cgi->param( 'SHOWMINE' ) );

  my $rettable;
  
  opendir( SSA, "$FIG_Config::data/MetaSubsystems" ) or die "Could not open $FIG_Config::data/MetaSubsystems";
  my @sss = readdir( SSA );
  
  my $retcolumns = [ { 'name' => 'Meta Name',
		       'width' => 300,
		       'sortable' => 1,
		       'filter'   => 1 },
		     { 'name' => 'Meta Owner',
		       'width' => 200,
		       'sortable' => 1,
		       'filter'   => 1 }
#		     { 'name' => '# subsystems',
#		       'sortable' => 1 }
  		   ];
  
  my $retdata = [];
  foreach ( @sss ) {
    next if ( $_ =~ /^\./ );

    my $name = $_;

    if ( defined( $name ) && $name ne '' && $name ne ' ' ) {  

      my $ssname = $name;
      $ssname =~ s/\_/ /g;

      my $esc_name = uri_escape($name);
      
      my $subsysurl = "SubsysEditor.cgi?page=MetaSpreadsheet&metasubsystem=$esc_name";
      my $owner = MetaSubsystem::get_curator_from_metaname( $name );
      
      my $retrow = [ "<A HREF='$subsysurl' target='_blank'>$ssname</A>",
		     $owner,
#		     "-"
		   ];
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
