package SubsystemEditor::WebPage::SubsystemOverview;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;
use Mail::Mailer;

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

  # look if someone is logged in and can write the subsystem #
  my $can_alter = 0;
  my $user = $self->application->session->user;
  if ( $user ) {
    $can_alter = 1;
  }

  my $dbmaster = $self->application->dbmaster;
  my $ppoapplication = $self->application->backend;

  # get a seeduser
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

  ######################
  # Construct the menu #
  ######################

  my $menu = $self->application->menu();

  # Build nice tab menu here
  $menu->add_category( 'To MetaSubsystems', "SubsysEditor.cgi?page=MetaOverview" );
  
  ##############################
  # Construct the page content #
  ##############################

  my $content = "<H2>Subsystems Overview</H2>";
  $content .= $self->start_form();
  $self->{ 'user' } = $user;
  if ( $user ) {
    $content .= "<INPUT TYPE=SUBMIT NAME='SHOWRIGHT' ID='SHOWRIGHT' VALUE='Show only Subsystems I can Edit'>";
    $content .= "<INPUT TYPE=SUBMIT NAME='SHOWMINE' ID='SHOWMINE' VALUE='Show only my Subsystems'>";
    $content .= "<INPUT TYPE=BUTTON NAME='NEWSUBSYS' ID='NEWSUBSYS' VALUE='Create new subsystem' onclick=\" window.open( '?page=NewSubsystem' )\">";
    $content .= "<INPUT TYPE=BUTTON NAME='MANAGESUBSYS' ID='MANAGESUBSYS' VALUE='Manage my subsystems' onclick=\" window.open( '?page=ManageSubsystems' )\">";
    $content .= "<INPUT TYPE=BUTTON NAME='MANAGEALLSUBSYS' ID='MANAGEALLSUBSYS' VALUE='Manage all subsystems I can Edit' onclick=\" window.open( '?page=ManageSubsystems&alleditable=1' )\">";
  }
  $content .= $self->end_form();

  my ( $sstable, $comment ) = getSubsystemTable( $self, $fig, $can_alter, $user, $seeduser );
  
  $content .= $sstable;

  return $content;
}


####################################
# get the subsystem overview table #
####################################
sub getSubsystemTable {
  
  my ( $self, $fig, $can_alter, $user, $seeduser ) = @_;
  
  my $cgi = $self->application->cgi;
  my $comment = '';

  my $showright = defined( $cgi->param( 'SHOWRIGHT' ) );
  my $showmine = defined( $cgi->param( 'SHOWMINE' ) );

  my $rettable;

  my @sss = $fig->all_subsystems_detailed();

  my $retcolumns = [ { 'name' => 'Classification 1',
		       'width' => 300,
		       'sortable' => 1,
		       'filter'   => 1 }, 
		     { 'name' => 'Classification 2',
		       'width' => 300,
		       'sortable' => 1,
		       'filter'   => 1 }, 
  		     { 'name' => 'Subsystem Name',
		       'width' => 300,
		       'sortable' => 1,
		       'filter'   => 1 },
		     { 'name' => 'Version',
		       'sortable' => 1 },
		     { 'name' => 'Mod Time',
		       'sortable' => 1 },
		     { 'name' => 'Subsystem Curator',
		       'width' => 200,
		       'sortable' => 1,
		       'filter'   => 1 },
		     { 'name' => 'Copy' },
  		   ];

  my $ss_rights = [];
  if ($user)
  {
      $ss_rights = $user->has_right_to($self->application, 'edit', 'subsystem');
  }
  $self->{ss_rights} = { map { $_ => 1 } @$ss_rights };
  
  my $retdata = [];
  foreach my $ss ( @sss ) {

      my $name = $ss->{subsystem};

      my $can_edit_this = $self->{ss_rights}->{'*'} || $self->{ss_rights}->{$name};
      
      if ( $showright && $user ) {
	  next unless $can_edit_this;
      }
      
      my $class = [$ss->{class_1}, $ss->{class_2}];

      my $ssversion = $ss->{version};
      my $sscurator = $ss->{curator};

      # CHANGE THIS TO THE RIGHT PREFERENCE OF THE USER... #
      if ( $showmine && $user ) {
	  next unless ( $seeduser eq $sscurator );
      }
      
      if ( defined( $name ) && $name ne '' && $name ne ' ' ) {  
	  
	  my $mod_time = &FIG::epoch_to_readable($ss->{last_update});
	  if ( $mod_time =~ /([^\:]+)\-([^\:]+)\-([^\:]+)\:.*/ ) {
	      $mod_time = $3.'-';
	      if ( length( $1 ) == 1 ) {
		  $mod_time .= '0'.$1.'-';
	      }
	      else {
		  $mod_time .= $1.'-';
	      }
	      if ( length( $2 ) == 1 ) {
		  $mod_time .= '0'.$2;
	      }
	      else {
		  $mod_time .= $2;
	      }
	  }
	  my $ssname = $name;
	  $ssname =~ s/\_/ /g;
	  
	  if ( $name =~ /\'/ ) {
	      $name =~ s/\'/&#39/g;
	      }
	  my $esc_name = uri_escape( $name );
	  
	  my $subsysurl = "SubsysEditor.cgi?page=ShowSubsystem&subsystem=$esc_name";
	  my $copy_link = "<A HREF='SubsysEditor.cgi?page=CopySubsystem&subsystem=$esc_name' target=_blank>copy</A>";
	  
	  if ( !defined( $self->{ 'user' } ) ) {
	      $copy_link = '';
	  }
	  
	  my $retrow = [ $class->[0] || "", 
			$class->[1] || "", 
			"<A HREF='$subsysurl' target='_blank'>$ssname</A>",
			$ssversion,
			$mod_time,
			$sscurator, 
			$copy_link
			];
	  push @$retdata, $retrow;
      }
  }
  
  my @retsorted = sort { $a->[0] cmp $b->[0] || $a->[1] cmp $b->[1] || $a->[2] cmp $b->[2] } @$retdata;

  my $rettableobject = $self->application->component( 'retttable' );
  $rettableobject->width( 900 );
  $rettableobject->data( \@retsorted );
  $rettableobject->columns( $retcolumns );
  $rettable = $rettableobject->output();
  
  return ( $rettable, $comment );
}

sub supported_rights {
  
return [ [ 'login', '*', '*' ] ];

}


sub get_mod_time {
  
  my ( $ssa, $fig ) = @_;

  my( $t, @spreadsheets );
  if ( opendir( BACKUP, "$FIG_Config::data/Subsystems/$ssa/Backup" ) ) {

    @spreadsheets = sort { $b <=> $a }
      map { $_ =~ /^spreadsheet.(\d+)/; $1 }
	grep { $_ =~ /^spreadsheet/ } 
	  readdir(BACKUP);
    closedir(BACKUP);

    if ( $t = shift @spreadsheets ) {
      my $last_modified = &FIG::epoch_to_readable( $t );
      if ( $last_modified =~ /([^\:]+)\-([^\:]+)\-([^\:]+)\:.*/ ) {
	my $val = $3.'-';
	if ( length( $1 ) == 1 ) {
	  $val .= '0'.$1.'-';
	}
	else {
	  $val .= $1.'-';
	}
	if ( length( $2 ) == 1 ) {
	  $val .= '0'.$2;
	}
	else {
	  $val .= $2;
	}
	return $val;
      }
    }
  }
  return "unknown";
}
