package SubsystemEditor::WebPage::ResetSubsystem;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;

use FIG;
use FIGV;
use UnvSubsys;

use base qw( WebPage );

1;

##################################################
# Method for registering components etc. for the #
# application                                    #
##################################################
sub init {
  my ( $self ) = @_;

  $self->application->register_component('Table', 'VersionTable');
}

sub require_javascript {

  return [ './Html/showfunctionalroles.js' ];

}

##############################################
# Website content is returned by this method #
##############################################
sub output {
  my ($self) = @_;

  # needed objects #
  $self->{ 'fig' } = new FIG;
  my $application = $self->application();
  $self->{ 'cgi' } = $application->cgi;
  
  # subsystem name and 'nice name' #
  my $name = $self->{ 'cgi' }->param( 'subsystem' );
  my $ssname = $name;
  $ssname =~ s/\_/ /g;

  my $esc_name = uri_escape($name);

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

  if ( $user && $user->has_right( $self->application, 'edit', 'subsystem', $name ) ) {
    $self->{ 'can_alter' } = 1;
    $self->{ 'fig' }->set_user( $seeduser );
  }

  $self->title( "Reset Subsystem Version" );
  
  my $hiddenvalues = {};
  
  $hiddenvalues->{ 'actionhidden' } = 'none'; 
  $hiddenvalues->{ 'pickedtime' } = 'none'; 
  $hiddenvalues->{ 'subsystem' } = $self->{ 'cgi' }->param( 'subsystem' ); 

  my $content = "<H2>Reset Subsystem</H2>";
  my $finished = 0;
  my ( $comment, $error ) = ( '', '' );
  
  if ( defined( $self->{ 'cgi' }->param( 'actionhidden' ) ) && $self->{ 'cgi' }->param( 'actionhidden' ) eq 'RESET' ) {
    my $ts = $self->{ 'cgi' }->param( 'CHOOSE' );
    if ( defined( $ts ) ) {
      ( $comment, $error ) = $self->reset_ssa_to( $name, $ts );
      if ( !defined( $error ) || $error eq '' ) {
	my $readablets = &FIG::epoch_to_readable( $ts );
	$content .= "Your subsystem has been reset the previous timestamp $readablets.<BR><BR> Please follow this link to get back to it:\n";
	$content .= "<A HREF='". $self->application->url() ."?page=ShowSubsystem&subsystem=$esc_name'>subsystem link<A>";
	$finished = 1;
      }
    }
  }
  if ( !$finished ) {
    $content .= "<P>Use this function to reset your subsystem to a previous version. Choose the version you want to reset to and press the button.<BR>The current version will be saved in the backup. Discard all browser windows that show the old version of the subsystem.<BR>Use the link to your subsystem that will appear on the next page.</P>";

    $self->get_reset_table( $name );

    $content .= $self->start_form( 'form', $hiddenvalues );

    if ( $self->{ 'can_alter' } ) {
      $content .= "<INPUT TYPE=BUTTON VALUE='Reset to selected timestamp' NAME='RESET' ONCLICK='if ( confirm( \"Do you really want reset the subsystem to the selected timestamp?\" ) ) { submitPage( \"RESET\", 0 ); }'>";
    }
    
    $content .= $self->application->component( 'VersionTable' )->output();
    $content .= $self->{ 'cgi' }->end_form();
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


sub get_reset_table {
  my( $self, $subsystem_name ) = @_;
  
  if ( opendir( BACKUP,"$FIG_Config::data/Subsystems/$subsystem_name/Backup" ) ) {
    
    my @spreadsheets = sort { $b <=> $a }
      map { $_ =~ /^spreadsheet.(\d+)/; $1 }
	grep { $_ =~ /^spreadsheet/ } 
	  readdir(BACKUP);
    closedir(BACKUP);
    
    my $col_hdrs;
    if ( $self->{ 'can_alter' } ) {
      $col_hdrs = [ '',
		    { name => 'Timestamp', filter => 1, sortable => 1 },
		    { name => 'By', filter => 1, sortable => 1 },
		    { name => '# Genomes', filter => 1, sortable => 1 },
		    { name => '# Func. Roles', filter => 1, sortable => 1 },
		    { name => '# Subsets', filter => 1, sortable => 1 },
		  ];
    }
    else {
      $col_hdrs = [ { name => 'Timestamp', filter => 1, sortable => 1 },
		    { name => 'By', filter => 1, sortable => 1 },
		    { name => '# Genomes', filter => 1, sortable => 1 },
		    { name => '# Func. Roles', filter => 1, sortable => 1 },
		    { name => '# Subsets', filter => 1, sortable => 1 },
		  ];
    }
    
    my $curhash = $self->{ 'fig' }->curation_history( $subsystem_name );

    my $tab = [];
    foreach my $t ( @spreadsheets ) {
      my $esc_name = uri_escape($subsystem_name);

      my $readable = &FIG::epoch_to_readable( $t );
      my $url = $self->application->url() . "?page=ShowSubsystem&subsystem=$esc_name&request=reset_to&ts=$t";
      my $link = "<a href=$url>$readable</a>";
      open(TMP,"<$FIG_Config::data/Subsystems/$subsystem_name/Backup/spreadsheet.$t")
	|| die "could not open $FIG_Config::data/Subsystems/$subsystem_name/Backup/spreadsheet.$t";

      my $area = 0;
      my @frs;
      my @genomes;
      my @subsets;
      # get the info #
      while ( my $l = <TMP> ) {
	chomp $l;
	if ( $l =~ /^\/\// ) {
	  $area++;
	  next;
	}
	if ( $area == 0 ) {
	  if ( $l =~ /([^\t]+)\t([^\t]+)/ ) {
	    push @frs, [ $1, $2 ];
	  }
	}
	elsif ( $area == 1 ) {
	  if ( $l =~ /([^\t]+)\t.*/ ) {
	    push @subsets, $1;
	  }
	}
	elsif ( $area == 2 ) {
	  if ( $l =~ /([^\t]+)\t.*/ ) {
	    push @genomes, $1;
	  }	  
	}
      }
      
      my $radiobox = "<INPUT TYPE=RADIO NAME='CHOOSE' VALUE='$t'>";

      my $curator = $curhash->{ $t }->{ 'curator' };
      if ( $self->{ 'can_alter' } ) {
	push( @$tab, [ $radiobox, $link, $curator, scalar @genomes, scalar @frs, scalar @subsets ] );
      }
      else {
	push( @$tab, [ $link, $curator, scalar @genomes, scalar @frs, scalar @subsets ] );
      }
    }
    
    my $table = $self->application->component( 'VersionTable' );
    $table->columns( $col_hdrs );
    $table->data( $tab );
  }
}


sub reset_ssa_to {
  my ( $self, $ssa, $ts ) = @_;

  my $comment = '';
  my $error = '';
  print STDERR $ssa." SUBSYTEM\n";

  my $subsystem = new Subsystem( $ssa, $self->{ 'fig' }, 0 );
  $subsystem->db_sync();
  $subsystem->write_subsystem( 1 );

  if ( defined( $ssa ) && defined( $ts ) && 
       ( -s "$FIG_Config::data/Subsystems/$ssa/Backup/spreadsheet.$ts" ) ) {
    
    system "cp", "-f", "$FIG_Config::data/Subsystems/$ssa/Backup/spreadsheet.$ts", "$FIG_Config::data/Subsystems/$ssa/spreadsheet";
    chmod( 0777, "$FIG_Config::data/Subsystems/$ssa/spreadsheet" );
    if ( -s "$FIG_Config::data/Subsystems/$ssa/Backup/notes.$ts" ) {
      system "cp", "-f", "$FIG_Config::data/Subsystems/$ssa/Backup/notes.$ts", "$FIG_Config::data/Subsystems/$ssa/notes";
      chmod( 0777,"$FIG_Config::data/Subsystems/$ssa/notes" );
      $comment .= "Resetting notes...<BR>\n";
    }
    
    if ( -s "$FIG_Config::data/Subsystems/$ssa/Backup/reactions.$ts" ) {
      system "cp", "-f", "$FIG_Config::data/Subsystems/$ssa/Backup/reactions.$ts", "$FIG_Config::data/Subsystems/$ssa/reactions";
      chmod( 0777,"$FIG_Config::data/Subsystems/$ssa/reactions" );
      $comment .= "Resetting reactions...<BR>\n";
    }
    
    if ( -s "$FIG_Config::data/Subsystems/$ssa/Backup/hope_reactions.$ts" ) {
      system "cp", "-f", "$FIG_Config::data/Subsystems/$ssa/Backup/hope_reactions.$ts", "$FIG_Config::data/Subsystems/$ssa/hope_reactions";
      chmod( 0777,"$FIG_Config::data/Subsystems/$ssa/hope_reactions" );
      $comment .= "Resetting hope reactions...<BR>\n";
    }
    
    if ( -s "$FIG_Config::data/Subsystems/$ssa/Backup/hope_reaction_notes.$ts" ) {
      system "cp", "-f", "$FIG_Config::data/Subsystems/$ssa/Backup/hope_reaction_notes.$ts", "$FIG_Config::data/Subsystems/$ssa/hope_reaction_notes";
      chmod( 0777,"$FIG_Config::data/Subsystems/$ssa/hope_reaction_notes" );
      $comment .= "Resetting hope reaction notes...<BR>\n";
    }
    
    if ( -s "$FIG_Config::data/Subsystems/$ssa/Backup/hope_reaction_links.$ts" ) {
      system "cp", "-f", "$FIG_Config::data/Subsystems/$ssa/Backup/hope_reaction_links.$ts", "$FIG_Config::data/Subsystems/$ssa/hope_reaction_links";
      chmod(0777,"$FIG_Config::data/Subsystems/$ssa/hope_reaction_links");
      $comment .= "Resetting hope reaction links...<BR>\n";
    }
    
    if ( -s "$FIG_Config::data/Subsystems/$ssa/Backup/hope_kegg_info.$ts" ) {
      system "cp", "-f", "$FIG_Config::data/Subsystems/$ssa/Backup/hope_kegg_info.$ts", "$FIG_Config::data/Subsystems/$ssa/hope_kegg_info";
      chmod(0777,"$FIG_Config::data/Subsystems/$ssa/hope_kegg_info");
      $comment .= "Resetting hope kegg info...<BR>\n";
    }
    
    my $subsystem = new Subsystem( $ssa, $self->{ 'fig' }, 0 );
    $subsystem->db_sync(0);
    undef $subsystem;
  }
  else {
    if ( !defined( $ssa ) ) {
      $error .= "No subsystem name given<BR>\n";
    }
    if ( !defined( $ts ) ) {
      $error .= "No timestamp given to reset to<BR>\n";
    }
  }
  return ( $comment, $error );
}
