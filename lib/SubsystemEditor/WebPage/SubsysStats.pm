package SubsystemEditor::WebPage::SubsysStats;

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
#    $content .= "<INPUT TYPE=SUBMIT NAME='SHOWRIGHT' ID='SHOWRIGHT' VALUE='Show only Subsystems I can Edit'>";
#    $content .= "<INPUT TYPE=SUBMIT NAME='SHOWMINE' ID='SHOWMINE' VALUE='Show only my Subsystems'>";
#    $content .= "<INPUT TYPE=BUTTON NAME='NEWSUBSYS' ID='NEWSUBSYS' VALUE='Create new subsystem' onclick=\" window.open( '?page=NewSubsystem' )\">";
#    $content .= "<INPUT TYPE=BUTTON NAME='MANAGESUBSYS' ID='MANAGESUBSYS' VALUE='Manage my subsystems' onclick=\" window.open( '?page=ManageSubsystems' )\">";
#    $content .= "<INPUT TYPE=BUTTON NAME='MANAGEALLSUBSYS' ID='MANAGEALLSUBSYS' VALUE='Manage all subsystems I can Edit' onclick=\" window.open( '?page=ManageSubsystems&alleditable=1' )\">";
  }

  my ( $sstable, $comment ) = getSubsystemTable( $self, $fig, $can_alter, $user, $seeduser );
  
  $content .= $self->end_form();
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
  
  opendir( SSA, "$FIG_Config::data/Subsystems" ) or die "Could not open $FIG_Config::data/Subsystems";
  my @sss = readdir( SSA );
  
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
		     { 'name' => 'Created',
		       'sortable' => 1,
		       'filter'   => 1 },
		     { 'name' => 'Mod Time',
		       'sortable' => 1,
		       'filter'   => 1 },
		     { 'name' => 'Subsystem Curator',
		       'width' => 200,
		       'sortable' => 1,
		       'filter'   => 1 },
		     { 'name' => '# roles',
		       'sortable' => 1 },
		     { 'name' => '# diagrams',
		       'sortable' => 1 },
		     { 'name' => '# illustrations',
		       'sortable' => 1 },
		     { 'name' => 'Copy' },
  		   ];
  
  my $retdata = [];
  foreach ( @sss ) {
    next if ( $_ =~ /^\./ );

    my $name = $_;

    if ( $showright && $user ) {
      next unless ( $user->has_right( $self->application, 'edit', 'subsystem', $name ) );
    }

    my $class = $fig->subsystem_classification( $name );
    
    my ( $ssversion, $sscurator, $pedigree, $ssroles ) = $fig->subsystem_info( $name );

    # CHANGE THIS TO THE RIGHT PREFERENCE OF THE USER... #
    if ( $showmine && $user ) {
      next unless ( $seeduser eq $sscurator );
    }

    if ( defined( $name ) && $name ne '' && $name ne ' ' ) {  

      my $mod_time = get_mod_time( $name );
      my $create_time = get_create_time( $name );

      my $ssname = $name;
      $ssname =~ s/\_/ /g;

      if ( $name =~ /'/ ) {
	$name =~ s/'/&#39/;
      }
      my $esc_name = uri_escape($name);

      my $numdiagrams = $fig->subsystem_num_diagrams( $name );
      my $count_new_diagrams = $fig->subsystem_num_new_diagrams( $name );
      my $numillustrations = $numdiagrams - $count_new_diagrams;

      if ( $count_new_diagrams > 0 ) {
	$count_new_diagrams = "<A HREF='SubsysEditor.cgi?page=ShowDiagram&subsystem=$esc_name' target='_blank'>$count_new_diagrams</A>"
      }
      if ( $numillustrations > 0 ) {
	$numillustrations = "<A HREF='SubsysEditor.cgi?page=ShowIllustrations&subsystem=$esc_name' target='_blank'>$numillustrations</A>"
      }
      
      my $subsysurl = "SubsysEditor.cgi?page=ShowSubsystem&subsystem=$esc_name";
      my $copy_link = "<A HREF='SubsysEditor.cgi?page=CopySubsystem&subsystem=$esc_name' target=_blank>copy</A>";

      if ( !defined( $self->{ 'user' } ) ) {
	$copy_link = '';
      }
      
      my $retrow = [ $class->[0], 
		     $class->[1], 
		     "<A HREF='$subsysurl' target='_blank'>$ssname</A>",
		     $ssversion,
		     $create_time,
		     $mod_time,
		     $sscurator, 
		     scalar( @$ssroles ),
		     $count_new_diagrams,
		     $numillustrations,
		     "$copy_link"
		   ];
      push @$retdata, $retrow;
    }
  }
  
  my $rettableobject = $self->application->component( 'retttable' );
  $rettableobject->width( 900 );
  $rettableobject->data( $retdata );
  $rettableobject->columns( $retcolumns );
  $rettableobject->show_top_browse( 1 );
  $rettableobject->show_select_items_per_page( 1 );
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

sub get_create_time {
  my ( $ssa, $fig ) = @_;
  if ( open( CURLOG, "$FIG_Config::data/Subsystems/$ssa/curation.log" ) ) {
    while (<CURLOG>) {
      if ( $_ =~ /(\d+)\t.*\tstarted/ ) {
	my $t = &FIG::epoch_to_readable( $1 );
	if ( $t =~ /([^\:]+)\-([^\:]+)\-([^\:]+)\:.*/ ) {
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
  }
  return 'unknown';

}
