package SubsystemEditor::WebPage::ShowSpreadsheet;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;
use DBMaster;

use FIG;

use WebColors;
use MIME::Base64;
use Data::Dumper;
use File::Spec;
use GenomeLists;
    eval { 
    	require FFs;
    };

use Observation qw(get_objects);

use SubsystemEditor::SubsystemEditor qw( fid_link moregenomes );
use base qw( WebPage );

1;

##############################################################
# Method for registering components etc. for the application #
##############################################################
sub init {
  my ( $self ) = @_;

  $self->application->register_component( 'Table', 'SubsystemSpreadsheet' );
  $self->application->register_component( 'TabView', 'functionTabView' );
  $self->application->register_component( 'Info', 'CommentInfo');
  $self->application->register_component( 'OrganismSelect', 'OSelect');
  $self->application->register_component( 'OrganismSelect', 'RSelect');
  $self->application->register_component( 'Hover', 'EmptyCells');
  $self->application->register_component( 'Table', 'VarDescTable'  );
  $self->application->register_component( 'Ajax', 'Ajax'  );

  $self->{ collapse_groups } = 1; 

  return 1;
}

sub require_javascript {

  return [ './Html/showfunctionalroles.js' ];

}

##############################################
# Website content is returned by this method #
##############################################
sub output {
  my $time = time;
  my ( $self ) = @_;

  # needed objects #
  $self->{ 'fig' } = $self->application->data_handle( 'FIG' );
  $self->{ 'cgi' } = $self->application->cgi;
  
  # subsystem name and 'nice name' #
  my $name = $self->{ 'cgi' }->param( 'subsystem' );
  my $ssname = $name;

  if ( $name =~ /^subsystem_checkbox_(.*)/ ) {
    $name = $1;
  }

  my $esc_name = uri_escape($name);

  $ssname =~ s/\_/ /g;

  # look if someone is logged in and can write the subsystem #
  $self->{ 'can_alter' } = 0;
  my $user = $self->application->session->user;

  my $dbmaster = $self->application->dbmaster();
  my $ppoapplication = $self->application->backend();
  

  ############################################
  ### GET PREFERENCES FOR AN EXISTING USER ###
  my $preferences = {};

  if ( defined( $user ) && ref( $user ) ) {
    my $pre = $self->application->dbmaster->Preferences->get_objects( { user        => $user,
									application => $ppoapplication } );
    %{ $preferences } = map { $_->name => $_ } @$pre;
  }
  ############################################

  # get a seeduser #
  $self->{ 'seeduser' } = '';

  if ( defined( $preferences->{ 'SeedUser' } ) ) {
    $self->{ 'seeduser' } = $preferences->{ 'SeedUser' }->value;
  }
  elsif ( defined( $user ) && ref( $user ) ) {
    $self->{ 'seeduser' } = $user->login();
  }
  if ( $user && $user->has_right( $self->application, 'edit', 'subsystem', $name ) ) {
    $self->{ 'can_alter' } = 1;
    $self->{ 'fig' }->set_user( $self->{ 'seeduser' } );
  }


  ##################################################
  # Now set some cgi parameters from user settings #
  ##################################################

  my $succ = setCGIParameter( $self, $user, $esc_name, 'uncollapse_set', $preferences, 1 );
  $succ = setCGIParameter( $self, $user, $esc_name, 'collection_set', $preferences, 1 );
  $succ = setCGIParameter( $self, $user, $esc_name, 'special_set', $preferences, 0 );
  $succ = setCGIParameter( $self, $user, $esc_name, 'phylogeny_set', $preferences, 0 );
  $succ = setCGIParameter( $self, $user, $esc_name, 'user_set', $preferences, 0 );

  ############ DONE SETTING PARAMETERS #################

  # get a subsystem object to handle it #
  my $subsystem = new Subsystem( $name, $self->{ 'fig' }, 0 );

  my ( $error, $comment ) = ( "", "" );
  my $activeSubsetHash;

  #########
  # TASKS #
  #########

  if ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'Add selected genome(s) to spreadsheet' ) {
    my @newGenomes = $self->{ 'cgi' }->param( 'new_genome' );
    my $specialsetlist = $self->{ 'cgi' }->param( 'add_special_set' );
    my $usersetlist = $self->{ 'cgi' }->param( 'add_user_set' );
    my $ghash = {};
    unless( $specialsetlist eq 'None' ) {
      my @subsetspecial = moregenomes( $self, $specialsetlist );
      my %tmpspecialhash = map { $_ => 1 } @subsetspecial;
      $ghash = \%tmpspecialhash;
    }
    unless( $usersetlist eq 'None' ) {
      $ghash = get_userlist_hash( $usersetlist, $ghash );
    }
    
    # take only the fig-tax id from the genome label #
    foreach my $g ( @newGenomes ) {
      $ghash->{ $g } = 1;
    }
    
    my @garray = keys %$ghash;
    my ( $puterror, $putcomment ) = $self->add_refill_genomes( $subsystem, \@garray, 1 );
    $error .= $puterror;
    $comment .= $putcomment;
  }
  if ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'Add selected region' ) {
    my @garray = $self->{ 'cgi' }->param( 'new_region' );
    if ( !defined( $garray[0] ) ) {
      $error .= "You have not selected a genome for your region!<BR>\n";
    }
    else {
      my $reg_loc = $self->{ 'cgi' }->param( 'region_location' );
      
      if ( $reg_loc eq 'Location:' ) {
	my $contig = $self->{ 'cgi' }->param( 'RegionContig' );
	my $start = $self->{ 'cgi' }->param( 'RegionStart' );
	my $stop = $self->{ 'cgi' }->param( 'RegionStop' );
	if ( !defined( $start ) ) {
	  $error .= "The start of your region is not defined. Please state a start position<BR>\n";
	}
	elsif ( !defined( $stop ) ) {
	  $error .= "The stop of your region is not defined. Please state a stop position<BR>\n";
	}
	elsif ( $start == $stop ) {
	  $error .= "The start and stop for the selected region is the same. Please correct this before I can put the region in !<BR>\n";
	}
	elsif ( !defined( $contig ) || $contig eq '' ) {
	  $error .= "You have not defined a contig for your region. Please correct this before I can put the region in !<BR>\n";
	}
	else {
	  if ( $start > $stop ) {
	    my $bet = $start;
	    $start = $stop;
	    $stop = $bet;
	  }
	  
	  my $contig_length = $self->{ 'fig' }->contig_lengths( $garray[0] );
	  
	  my $clen = $contig_length->{ $contig };
	  
	  if ( $stop > $clen ) {
	    $error .= "Your stop is larger than the contig length. Please specify a valid stop position for your region!<BR>\n";
	  }
	  if ( $start < 0 ) {
	    $error .= "Sigh. Negative Start positions?<BR>\n";
	  } 
	  else {
	    my $locgenome = $garray[0].":".$contig."_".$start."_".$stop;
	    my ( $puterror, $putcomment ) = $self->add_refill_genomes( $subsystem, [ $locgenome ], 1 );
	    $error .= $puterror;
	    $comment .= $putcomment;
	  }
	}
      }
      else {
	my $peg1 = $self->{ 'cgi' }->param( 'RegionPeg1' );
	my $peg2 = $self->{ 'cgi' }->param( 'RegionPeg2' );
	
	if ( !defined( $peg1 ) ) {
	  $error .= "Peg 1 is not defined, so I cannot put the region in !<BR>\n";
	}
	elsif ( !defined( $peg2 ) ) {
	  $error .= "Peg 2 is not defined, so I cannot put the region in !<BR>\n";
	}
	else { 

	  if ( $peg1 !~ /fig\|\d+\.\d+\.peg\.\d+/ && $peg1 =~ /^\d+$/ ) {
	    $peg1 = "fig\|".$garray[0].".peg.".$peg1;
	  }
	  if ( $peg2 !~ /fig\|\d+\.\d+\.peg\.\d+/ && $peg2 =~ /^\d+$/ ) {
	    $peg2 = "fig\|".$garray[0].".peg.".$peg2;
	  }

	  my @vals;

	  my $loc = $self->{ 'fig' }->feature_location( $peg1 );
	  my( $contig1, $beg1, $end1 ) = $self->{ 'fig' }->boundaries_of( $loc );
	  push @vals, $beg1;
	  push @vals, $end1;
	  $loc = $self->{ 'fig' }->feature_location( $peg2 );
	  my ( $contig2, $beg2, $end2 ) = $self->{ 'fig' }->boundaries_of( $loc );
	  push @vals, $beg2;
	  push @vals, $end2;
	  
	  if ( !defined( $contig1 ) ) {
	    $error .= "The peg $peg1 does not have a location in that genome\n";
	  }
	  elsif ( !defined( $contig2 ) ) {
	    $error .= "The peg $peg2 does not have a location in that genome\n";
	  }
	  elsif ( $contig1 ne $contig2 ) {
	    $error .= "The two pegs you have stated are not on the same contig! Please correct this before I can put the region in !<BR>\n";
	  }
	  else {
	    my $start = $self->{ 'fig' }->min( @vals );
	    my $stop = $self->{ 'fig' }->max( @vals );
	    
	    my $locgenome = $garray[0].":".$contig1."_".$start."_".$stop;
	    my ( $puterror, $putcomment ) = $self->add_refill_genomes( $subsystem, [ $locgenome ], 1 );
	    $error .= $puterror;
	    $comment .= $putcomment;	  
	  }
	}
      }
    }
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'RefillSelectionButton' ) {
    my @newGenomes = $self->{ 'cgi' }->param( 'genome_checkbox' );
    
    # take only the fig-tax id from the genome label #
    @newGenomes = map { $_ =~ /^genome_checkbox_(\d+\.\d+)/; $1 } @newGenomes;
    
    my ( $puterror, $putcomment ) = $self->add_refill_genomes( $subsystem, \@newGenomes, 0 );
    $error .= $puterror;
    $comment .= $putcomment;
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'FillSelectionButton' ) {
    my @newGenomes = $self->{ 'cgi' }->param( 'genome_checkbox' );
    
    # take only the fig-tax id from the genome label #
    @newGenomes = map { $_ =~ /^genome_checkbox_(\d+\.\d+)/; $1 } @newGenomes;
    
    my ( $puterror, $putcomment ) = $self->add_refill_genomes( $subsystem, \@newGenomes, 0, 1 );
    $error .= $puterror;
    $comment .= $putcomment;
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'RefillAllButton' ) {
    
    my ( $puterror, $putcomment ) = $self->add_refill_genomes( $subsystem, 'All', 0 );
    $error .= $puterror;
    $comment .= $putcomment;
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'FillAllButton' ) {
    my ( $puterror, $putcomment ) = $self->add_refill_genomes( $subsystem, 'All', 0, 1 );
    $error .= $puterror;
    $comment .= $putcomment;
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'DeleteGenomes' ) {
    my @genomesIds = $self->{ 'cgi' }->param( 'genome_checkbox' );
    my ( $putcomment ) = $self->remove_genomes( $subsystem, \@genomesIds );
    $comment .= $putcomment;
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'SaveVariants' ) {
    my ( $puterror, $putcomment ) = $self->save_variant_codes( $subsystem );
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'ShowOnlyButton' ) {
    my @selGenomes = $self->{ 'cgi' }->param( 'genome_checkbox' );
    my %sG;
    foreach my $genm ( @selGenomes ) {
      $genm =~ /^genome_checkbox_(\d+\.\d+)/;
      my $genome = $1;
      if ( defined( $genome ) && $genome ne '' ) {
	$sG{ $genome } = 1;
      }
    }  
    $activeSubsetHash = \%sG;
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'ColorSimsButton' ) {
    my @selGenomes = $self->{ 'cgi' }->param( 'genome_checkbox' );
    my $genm = $selGenomes[0];
    $genm =~ /^genome_checkbox_(\d+\.\d+)/;
    $self->{ 'colorsimsgenome' } = $1;
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'ColorPidentButton' ) {
    my @selGenomes = $self->{ 'cgi' }->param( 'genome_checkbox' );
    my $genm = $selGenomes[0];
    $genm =~ /^genome_checkbox_(\d+\.\d+)/;
    $self->{ 'colorpidentgenome' } = $1;
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'SHOWEMPTYCELLS' ) {
    $self->{ 'cgi' }->param( 'SHOWEMPTYCELLS', 1 );
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'NOSHOWEMPTYCELLS' ) {
    $self->{ 'cgi' }->param( 'SHOWEMPTYCELLS', 0 );
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'SAVEEMPTYCELLS' ) {
    $self->{ 'cgi' }->param( 'SHOWEMPTYCELLS', 1 );
    my @allbuttons = $self->{ 'cgi' }->param( 'EMPTYCELLHIDDENS' );

    my $emptycellsvalues = $subsystem->get_emptycells();

    foreach my $b ( @allbuttons ) {
      $b =~ /HIDDEN(.*)/;
      $b = $1;
      my ( $frl, $gnm, $vl ) = split( '##-##', $b );
      if ( $vl ne '?' ) {
	$emptycellsvalues->{ $frl }->{ $gnm } = $vl;
      }
    }
    $subsystem->set_emptycells( $emptycellsvalues );
    $subsystem->write_subsystem();
  }
  if ( !defined( $activeSubsetHash ) ) {
    $activeSubsetHash = $self->getActiveSubsetHash( $subsystem );
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

 
  ##############################
  # Construct the page content #
  ##############################

  my $content = "<H1>Spreadsheet for Subsystem: $ssname</H1>";

  if ( defined( $comment ) && $comment ne '' ) {
    my $info_component = $self->application->component( 'CommentInfo' );

    $info_component->content( $comment );
    $info_component->default( 0 );
    $content .= $info_component->output();
  }    

  # create the subsystem spreadsheet
  my ( $legend, $legendg, $frscrlist, $hiddenvalues, $emptycellshover ) = $self->load_subsystem_spreadsheet( $preferences, $name, $subsystem, $user, $activeSubsetHash );

  # addgenomespanel #
  my $addgenomepanel = $self->add_genomes_panel( $subsystem );
  # addregionpanel #
  my $addregionpanel = $self->add_region_panel( $subsystem );
  # colorpanel #
  my $colorpanel = $self->color_spreadsheet_panel( $preferences, $name );
  # limitdisplaypanel #
  my $limitdisplaypanel = $self->limit_display_panel( $subsystem );
  # showvariantspanel #
  my $variantpanel = $self->variant_panel( $subsystem, $name );

  # the spreadsheet #
  my $spreadsheet_tab = "<H2>Subsystem Spreadsheet</H2>";
  $spreadsheet_tab .= $self->application->component( 'SubsystemSpreadsheet' )->output();

  # spreadsheetbuttons #
  my $spreadsheetbuttons1 = $self->get_spreadsheet_buttons( $name, $frscrlist, 1 );
  my $spreadsheetbuttons2 = $self->get_spreadsheet_buttons( $name, $frscrlist );

  # add hidden parameter for the tab that is actually open #
  my $dth = 0;
  if ( defined( $self->{ 'cgi' }->param( 'defaulttabhidden' ) ) ) {
    $dth = $self->{ 'cgi' }->param( 'defaulttabhidden' );
  }

  $hiddenvalues->{ 'subsystem' } = $name;
  $hiddenvalues->{ 'buttonpressed' } = 'none';
  $hiddenvalues->{ 'defaulttabhidden' } = $dth;
  if ( $self->{ 'cgi' }->param( 'SHOWEMPTYCELLS' ) ) {
    $hiddenvalues->{ 'SHOWEMPTYCELLS' } = 1;
  }

  # start form #
  $content .= $self->start_form( 'subsys_spreadsheet', $hiddenvalues );
  $content .= "<TABLE><TR><TD>";

  my $tab_view_component = $self->application->component( 'functionTabView' );
  $tab_view_component->width( 900 );
  if ( $self->{ 'can_alter' } ) {
    $tab_view_component->add_tab( '<H2>&nbsp; Add Genomes &nbsp;</H2>', "$addgenomepanel" );
    $tab_view_component->add_tab( '<H2>&nbsp; Add Regions &nbsp;</H2>', "$addregionpanel" );
  }
  $tab_view_component->add_tab( '<H2>&nbsp; Color Spreadsheet &nbsp;</H2>', "$colorpanel" );
  $tab_view_component->add_tab( '<H2>&nbsp; Limit Display &nbsp;</H2>', "$limitdisplaypanel" );
  $tab_view_component->add_tab( '<H2>&nbsp; Show Variants &nbsp;</H2>', "$variantpanel" );

  if ( defined( $self->{ 'cgi' }->param( 'defaulttabhidden' ) ) ) {
    $tab_view_component->default( $self->{ 'cgi' }->param( 'defaulttabhidden' ) );
  }
  else {
    $tab_view_component->default( 0 );
  }

  $content .= $tab_view_component->output();
  $content .= "</TD></TR><TR><TD>";

  # put in color legends #
  if ( defined( $legend ) ) {
    $content .= $legend;
    $content .= "</TD></TR><TR><TD>";
  }
  if ( defined( $legendg ) ) {
    $content .= $legendg;
    $content .= "</TD></TR><TR><TD>";
  }

  $content .= $spreadsheetbuttons1;
  $content .= "</TD></TR><TR><TD>";
  $content .= $spreadsheet_tab;
  $content .= "</TD></TR><TR><TD>";
  $content .= $spreadsheetbuttons2;
  $content .= "</TD></TR>";
  $content .= "</TABLE>";

  $content .= $self->{ 'columnrolehidden' };
  # end form 
  $content .= $self->end_form();

  ###############################
  # Display errors and comments #
  ###############################
 
  if ( defined( $error ) && $error ne '' ) {
    $self->application->add_message( 'warning', $error );
  }
  $content .= $emptycellshover->output();

  return $content;
}

##############################
# draw subsystem spreadsheet #
##############################
sub load_subsystem_spreadsheet {
  my ( $self, $preferences, $subsystem_name, $subsystem, $user, $activeSubsetHash, $collectionset, $starset ) = @_;

  my $emptycellshover = $self->application->component( 'EmptyCells' );

  # initialize roles, subsets and spreadsheet
  my ( $roles, $subsets, $collections, $spreadsheet_hash, $pegsarr, $peg_functions ) = $self->get_subsystem_data( $subsystem, $subsystem_name, $emptycellshover, $self->{ 'cgi' }->multi_param( 'SHOWEMPTYCELLS' ) );

  # Displaying and Collapsing Subsets
  my @collection_set = ( 'All' );
  if ( defined( $self->{ 'cgi' }->param( 'collection_set' ) ) ) {
    @collection_set = $self->{ 'cgi' }->param( 'collection_set' );
  }
  my %collset = map { $_ => 1 } @collection_set;

  my @uncollapse_set = ( 'None' );
  if ( defined( $self->{ 'cgi' }->param( 'uncollapse_set' ) ) ) {
    @uncollapse_set = $self->{ 'cgi' }->param( 'uncollapse_set' );
  }
  my %uncollapse = map { $_ => 1 } @uncollapse_set;

  my $lookatcollections = 1;
  if ( defined( $collset{ 'All' } ) ) {
    $lookatcollections = 0;
  }

  my $uncollapseall = 0;
  if ( defined( $uncollapse{ 'All' } ) ) {
    $uncollapseall = 1;
  }

  # Now - what roles or what subsets do I take?
  my %takeroles;

  if ( $lookatcollections ) {
    # here get the roles to show, also the subsets so that we can look them up from the hash
    foreach my $subset ( keys %$collections ) {
      next if ( !defined( $collset{ $subset } ) );
      foreach my $role ( @{ $collections->{ $subset } } ) {
	$takeroles{ $roles->[ $role - 1 ]->[0] } = 1;
      }
      $takeroles{ $subset } = 1;
    }
  }

  # get a list of sane colors
  my $colors = $self->get_colors();

  # map roles to groups for quick lookup
  my $role_to_group;
  foreach my $subset ( keys %$subsets ) {
    next if ( $uncollapseall || defined( $uncollapse{ $subset } ) );
#    next if ( $lookatcollections && !( defined( $takeroles{ $subset } ) ) );

    foreach my $role ( @{ $subsets->{ $subset } } ) {
      push @{ $role_to_group->{ $roles->[ $role - 1 ]->[0] } }, $subset;
    }
  }

  # collect column names
  my $columns;
  my $role_to_function;
  my $function_to_role;
  my $toshowroles;
  foreach my $role ( @$roles ) {
    $toshowroles->{$role->[0]}=1;
    my $hr = 'THISROLE_'.$role->[0];
    $self->{ 'columnrolehidden' } .= $self->{ 'cgi' }->hidden( { id => $hr,
								 value => $role->[1] } );
    next if ( $lookatcollections && !( defined( $takeroles{ $role->[0] } ) ) );
    $role_to_function->{ $role->[0] } = $role->[1];
    $function_to_role->{ $role->[1] } = $role->[2];

    # look if this role is part of a subset
    if ( exists( $role_to_group->{ $role->[0] } ) ) {
      # look if we already have all subsets this role is in
      my $subsetsofthisrole = $role_to_group->{ $role->[0] };
      foreach my $ss ( @$subsetsofthisrole ) {
	unless ( exists( $columns->{ $ss } ) ) {
	  $columns->{ $ss } = scalar( keys %$columns );
	}
      }
    } 
    else {
      # role is not part of a subset, so show it
      $columns->{ $role->[0] } = scalar( keys %$columns );
    }
  }

  my $rolelist .= $self->{ 'cgi' }->scrolling_list( -id       => 'rolelist',
					-name     => 'rolelist',
					-multiple  => 1,
					-values   => [sort {$a cmp $b} keys %$toshowroles],
					-default  => '',
					-size     => 3
				      );

  ##########################################
  # COLORING SETTINGS OF GENES AND GENOMES #
  ##########################################
  my $peg_to_color_alround;
  my $cluster_colors_alround = {};
  my $legend;
  my $genome_colors;
  my $genomes_to_color = {};
  my $legendg;
  my $columnNameHash;

  ### COLOR GENES ###
#  my $color_by = 'do not color'; #default
  my $color_by = 'by cluster'; #default
  if ( $preferences->{ $subsystem_name."_color_stuff" } ) {
    $color_by = $preferences->{ $subsystem_name."_color_stuff" }->value;
  }
  if ( defined( $self->{ 'cgi' }->param( 'color_stuff' ) ) ) {
    $color_by = $self->{ 'cgi' }->param( 'color_stuff' );
    if ( $color_by ne 'simsgenome' && $color_by ne 'colorpidentgenome' && $color_by ne 'by FIGfams' && $color_by ne 'by inconsistencies' ) {
      unless ( $preferences->{ $subsystem_name."_color_stuff" } ) {
	if ( defined( $user ) && ref( $user ) ) {
	  $preferences->{ $subsystem_name."_color_stuff" } = $self->application->dbmaster->Preferences->create( { user        => $user,
														  application => $self->application->backend,
														  name        => $subsystem_name."_color_stuff",
														  value       => $color_by } );
	}
      }
      else {
	$preferences->{ $subsystem_name."_color_stuff" }->value( $color_by );
      }
    }
  }
  elsif ( $preferences->{ $subsystem_name."_color_stuff" } ) {
    $self->{ 'cgi' }->param( 'color_stuff', $preferences->{ $subsystem_name."_color_stuff" }->value );
  }

  if ( defined( $self->{ 'colorsimsgenome' } ) ) {
    $color_by = 'simsgenome';
  }
  elsif ( defined( $self->{ 'colorpidentgenome' } ) ) {
    $color_by = 'pidentgenome';
  }

  if ( $color_by eq 'by attribute: ' ) {
    my $attr = 'Essential_Gene_Sets_Bacterial';
    
    if ( $preferences->{ $subsystem_name."_color_by_peg_tag" } ) {
      $attr = $preferences->{ $subsystem_name."_color_by_peg_tag" }->value;
    }
    if ( defined( $self->{ 'cgi' }->param( 'color_by_peg_tag' ) ) ) {
      $attr = $self->{ 'cgi' }->param( 'color_by_peg_tag' );
      unless ( $preferences->{ $subsystem_name."_color_by_peg_tag" } ) {
	if ( $user ) {
	  $preferences->{ $subsystem_name."_color_by_peg_tag" } = $self->application->dbmaster->Preferences->create( { user        => $user,
														       application => $self->application->backend,
														       name        => $subsystem_name."_color_by_peg_tag",
														       value       => $attr } );
	}
      }
      else {
	$preferences->{ $subsystem_name."_color_by_peg_tag" }->value( $attr );
      }
    }
    ( $peg_to_color_alround, $cluster_colors_alround, $legend ) = $self->get_color_by_attribute_infos( $attr, $pegsarr, $colors );
  }
  elsif ( $color_by eq 'simsgenome' ) {
    ( $peg_to_color_alround, $cluster_colors_alround, $legend ) = $self->get_color_by_sims( $pegsarr, $colors, $spreadsheet_hash, 'evalue' );
  }
  elsif ( $color_by eq 'pidentgenome' ) {
    ( $peg_to_color_alround, $cluster_colors_alround, $legend ) = $self->get_color_by_sims( $pegsarr, $colors, $spreadsheet_hash, 'pident' );
  }
  elsif ( $color_by eq 'by FIGfams' ) {
    ( $peg_to_color_alround, $cluster_colors_alround, $legend ) = $self->get_color_by_attribute_infos( 'figfams', $pegsarr, $colors );
  }
  elsif ( $color_by eq 'by inconsistencies' ) {
    ( $peg_to_color_alround, $cluster_colors_alround, $legend ) = $self->get_color_by_check( $peg_functions, $colors, $spreadsheet_hash, $subsystem );
  }

  ### COLOR GENOMES ###
  my $colorg_by = 'do not color';
  if ( $preferences->{ $subsystem_name."_colorg_stuff" } ) {
    $colorg_by = $preferences->{ $subsystem_name."_colorg_stuff" }->value;
  }
  if ( defined( $self->{ 'cgi' }->param( 'colorg_stuff' ) ) ) {
    $colorg_by = $self->{ 'cgi' }->param( 'colorg_stuff' );
    unless ( $preferences->{ $subsystem_name."_colorg_stuff" } ) {
      if ( $user ) {
	$preferences->{ $subsystem_name."_colorg_stuff" } = $self->application->dbmaster->Preferences->create( { user        => $user,
														 application => $self->application->backend,
														 name        => $subsystem_name."_colorg_stuff",
														 value       => $color_by } );
      }
    }
    else {
      $preferences->{ $subsystem_name."_colorg_stuff" }->value( $colorg_by );
    }
  }
  elsif ( $preferences->{ $subsystem_name."_colorg_stuff" } ) {
    $self->{ 'cgi' }->param( 'colorg_stuff', $preferences->{ $subsystem_name."_colorg_stuff" }->value );
  }

  if ( $colorg_by eq 'by attribute: ' ) {
    
    my $attr;
    if ( $preferences->{ $subsystem_name."_color_by_ga" } ) {
      $attr = $preferences->{ $subsystem_name."_color_by_ga" }->value;
    }

    if ( defined( $self->{ 'cgi' }->param( 'color_by_ga' ) ) && $self->{ 'cgi' }->param( 'color_by_ga' ) ne '' ) {
      $attr = $self->{ 'cgi' }->param( 'color_by_ga' );

      unless ( $preferences->{ $subsystem_name."_color_by_ga" } ) {
	if ( $user ) {
	  $preferences->{ $subsystem_name."_color_by_ga" } = $self->application->dbmaster->Preferences->create( { user        => $user,
														  application => $self->application->backend,
														  name        => $subsystem_name."_color_by_ga",
														  value       => $attr } );
	}
      }
      elsif ( defined( $attr ) ) {
	$preferences->{ $subsystem_name."_color_by_ga" }->value( $attr );
	$self->{ 'cgi' }->param( 'color_by_ga', $attr );
      }
      ( $genomes_to_color, $genome_colors, $legendg ) = $self->get_color_by_attribute_infos_for_genomes( $spreadsheet_hash, $colors );
    }
  }

  ## END OF COLORING SETTINGS ##

  ################################
  # Creating the table from here #
  ################################

  # create table headers
  my $table_columns = [ '', 
			{ name => 'Organism', filter => 1, sortable => 1, width => '150', operand => $self->{ 'cgi' }->param( 'filterOrganism' ) || '' }, 
			{ name => 'Domain', filter => 1, operator => 'combobox', operand => $self->{ 'cgi' }->param( 'filterDomain' ) || '' }, 
			{ name => 'Taxonomy', sortable => 1, visible => 0, show_control => 1 }, 
			{ name => 'Variant', sortable => 1 }
		      ];
    

  my $ii = 4; # this is for keeping in mind in what column we start the Functional Roles

  # if user can write he gets a writable variant column that if first invisible
  if ( $self->{ 'can_alter' } ) {
    push @$table_columns, { name => 'Variant', visible => 0 };
    $ii++;
  }

  my $i = $ii;

  ### Now add the column headers for all functional roles or subsets of the table ###
  foreach my $column ( sort { $columns->{ $a } <=> $columns->{ $b } } keys( %$columns) ) {
    $i++;
    my $tooltip;
    if ( exists( $role_to_function->{ $column } ) ) {
      $tooltip = $role_to_function->{ $column };
    }
    else {
      $tooltip = "<table>";
      foreach my $role ( @{ $subsets->{ $column } } ) {
	$tooltip .= "<tr><td>$role</td><td><b>" . $roles->[$role - 1]->[0] . "</b></td><td>" . $roles->[$role - 1]->[1] . "</td></tr>";
      }
      $tooltip .= "</table>";
    }

    my $alink = "ss_directed_compare_regions.cgi?ss=$subsystem_name&abbr=$column";
    
    push( @$table_columns, { name => "<a href='$alink' target='_blank'>$column</a>", tooltip =>  $tooltip, filter => 1, operator => 'all_or_nothing' });
    $columnNameHash->{ $i } = $column.'<BR>'.$tooltip;
  }
  push( @$table_columns, { name => 'Pattern', sortable => 1, visible => 0, show_control => 1 });
  push( @$table_columns, { name => '# Clustered', sortable => 1, visible => 0, show_control => 1, filter => 1, operators => [ 'more', 'equal', 'less' ] });
  

  # Variants - default is not to show the -1 variants, so we have to ask if that is still true.
  my $show_mo_variants = 0;

  my $shmo = $self->application->dbmaster->Preferences->get_objects( { user => $user,
								       name => 'show_hide_minus_one' } );
  if ( defined( $shmo->[0] ) ) {
    my $show_hide_minus_one = $shmo->[0]->value();
    print STDERR $show_hide_minus_one." SHMO\n";
    if ( $show_hide_minus_one eq 'show' ) {
      $show_mo_variants = 1;
    }
  }
  
  if ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'MoVariants' || $self->{ 'cgi' }->param( 'showMoVariants' ) ) {
    $show_mo_variants = 1;
  }
  if ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'HideMoVariants' ) {
    $show_mo_variants = 0;
  }

  my $variantsdescs = $subsystem->get_variants();

  # For the lines of the table, walk through spreadsheet hash #
  my $pretty_spreadsheet;
 
  my @sortedrows;

  if ( $preferences->{ 'sort_spreadsheet_by' } && $preferences->{ 'sort_spreadsheet_by' }->value() eq 'alphabetically' ) {
    @sortedrows = sort { $spreadsheet_hash->{ $a }->{ 'name' } cmp $spreadsheet_hash->{ $b }->{ 'name' } } keys %$spreadsheet_hash;
  }
  else {
    @sortedrows = sort { $spreadsheet_hash->{ $a }->{ 'taxonomy' } cmp $spreadsheet_hash->{ $b }->{ 'taxonomy' } } keys %$spreadsheet_hash;
  }

  foreach my $g ( @sortedrows ) {
    if ( defined( $activeSubsetHash ) ) {
      next unless ( $activeSubsetHash->{ $g } );
    }

    my $new_row;
    
    # organism name, domain, taxonomy, variantcode #
    my $gname = $spreadsheet_hash->{ $g }->{ 'name' };
    my $domain = $spreadsheet_hash->{ $g }->{ 'domain' };
    my $tax = $spreadsheet_hash->{ $g }->{ 'taxonomy' };
    my $variant = $spreadsheet_hash->{ $g }->{ 'variant' };

    unless ( $show_mo_variants ) {
      next if ( $variant eq '-1' );
    }

    my $vardesc = $variantsdescs->{ $variant };
    if ( !defined( $vardesc ) ) {
      $vardesc = '-';
    }

    # add link to Organism page here #
    $gname = "<A HREF='seedviewer.cgi?page=Organism&organism=" . $g."' target=_blank>$gname</A>";

    my $gentry = $gname . ' ('. $g . ')';
    if ( defined( $genomes_to_color->{ $g } ) ) {
      $gentry = "<span style='background-color: " . $genome_colors->{ $genomes_to_color->{ $g } } . ";'>$gname (".$g.")</span>";
    }

    my $genome_checkbox = $self->{ 'cgi' }->checkbox( -name     => 'genome_checkbox',
					  -id       => "genome_checkbox_$g",
					  -value    => "genome_checkbox_$g",
					  -label    => '',
					  -checked  => 0,
					  -override => 1,
					);
    
    push( @$new_row, $genome_checkbox );
    push( @$new_row, $gentry );
    push( @$new_row, $domain );
    push( @$new_row, $tax );
    push( @$new_row, { data => "$variant <INPUT TYPE=HIDDEN ID=\"variant$g\" VALUE=\"$variant\">", tooltip => "<B>Variant Description</B><BR>$vardesc" }  );
    if ( $self->{ 'can_alter' } ) {
      push( @$new_row, "<INPUT TYPE=TEXT NAME=\"variant$g\" ID=\"variant$g\" SIZE=5 VALUE=\"$variant\">" );
    }

    # now the genes #
    my $thisrow = $spreadsheet_hash->{ $g }->{ 'row' };
    my @row = @$thisrow;

    # memorize all pegs of this row
    my $pegs;
    my $rawpegs;

    # go through data cells and do grouping
    my $data_cells;

    for ( my $i=0; $i<scalar( @row ); $i++ ) {
      push( @$pegs, split( /, /, $row[$i] ) );
      next if ( $lookatcollections && !( defined( $takeroles{ $roles->[ $i ]->[ 0 ] } ) ) );
      if ( exists( $role_to_group->{ $roles->[$i]->[0] } ) && $self->collapse_groups() ) {
	my $subsetsofthisrole = $role_to_group->{ $roles->[$i]->[0] };

	my $thiscell = '';
	foreach my $ss ( @$subsetsofthisrole ) {
	  my $index = $columns->{ $ss };
	  unless ( $row[$i] =~ /INPUT/ ) {
	    push( @{ $data_cells->[ $index ] }, split( /, /, $row[$i] ) );
	  }
	}	  
      } 
      else {
	my $index = $columns->{ $roles->[$i]->[0] };
	push( @{ $data_cells->[ $index ] }, split( /, /, $row[$i] ) );
      }
    }

    foreach my $p ( @$pegs ) {
      if ( $p =~ /(fig\|\d+\.\d+\.\w+\.\d+)/ ) {
	push @$rawpegs, $p;
      } 
    }

    my $peg_fns = $self->{fig}->function_of_bulk($rawpegs);

    my $peg_to_color;
    my $cluster_colors;

    # if we wanna color by cluster put it in here 
    if ( $color_by eq 'by cluster' ) {

      # compute clusters
      my @clusters = $self->{ 'fig' }->compute_clusters( $rawpegs, undef, 5000 );

      for ( my $i = 0; $i < scalar( @clusters ); $i++ ) {

	my %countfunctions = map{ ($peg_fns->{$_} => 1 ) } @{ $clusters[ $i ] };
	next unless ( scalar( keys %countfunctions ) > 1);

	foreach my $peg ( @{ $clusters[ $i ] } ) {
	  $peg_to_color->{ $peg } = $i;
	}
      }
    }
    elsif ( $color_by eq 'by attribute: ' || $color_by eq 'by FIGfams' || $color_by eq 'by inconsistencies' || $color_by eq 'simsgenome' || $color_by eq 'pidentgenome' ) {
      $peg_to_color = $peg_to_color_alround;
      $cluster_colors = $cluster_colors_alround;
    }

    # print actual cells
    my $pattern = "a";
    my $pat_num_clustered = 0;
    my $ind = $ii;
    foreach my $data_cell ( @$data_cells ) {
      $ind++;
      my $num_clustered = 0;
      my $num_unclustered = 0;
      my $cluster_num = 0;
      if ( defined( $data_cell ) ) {
	$data_cell = [ sort( @$data_cell ) ];
	my $cell = [];

	foreach my $peg ( @$data_cell ) {
	  
	  if ( $peg =~ /(fig\|\d+\.\d+\.\w+\.\d+)/ ) {
	    my $thispeg = $1;
	    my $pegf = $peg_functions->{ $thispeg } || '';
	    my $pegfnum = '';
	    
	    my @frs = split( ' [/@;] ', $pegf );
	    foreach my $funcstring ( @frs ) {
	      if ( $funcstring =~ /(.*\S)\s*#.*/ ) {
		$funcstring = $1;
	      }
	      my $abbpegf = $subsystem->get_abbr_for_role( $funcstring );
	      
	      if ( defined( $abbpegf ) && exists( $role_to_group->{ $abbpegf } ) ) {
		my $pegfnumtmp = $function_to_role->{ $funcstring };
		if ( defined( $function_to_role->{ $funcstring } ) ) {
		  $pegfnumtmp++;
		  $pegfnum .= '_'.$pegfnumtmp;
		}
		else {
		  print STDERR "No Function found in the subsystem for peg ".$pegf."\n";
		}
	      }
	    }
	    
	    if ( !defined( $thispeg ) ) {
	      next; 
	    }
	    
	    my ( $type, $num ) = $thispeg =~ /fig\|\d+\.\d+\.(\w+)\.(\d+)/;
	    my $n = $num;
	    if ( $type ne 'peg' ) {
	      $n = $type.'.'.$n;
	    }
	    my $peg_link = fid_link( $self, $thispeg );
	    $peg_link = "<A HREF='$peg_link' target=_blank>$n</A>";
	    $peg_link .= $pegfnum;
	    if ( exists( $peg_to_color->{ $peg } ) ) {
	      unless ( defined( $cluster_colors->{ $peg_to_color->{ $peg } } ) ) {
		$cluster_colors->{ $peg_to_color->{ $peg } } = $colors->[ scalar( keys( %$cluster_colors ) ) ];
	      }
	      $cluster_num = scalar( keys( %$cluster_colors ) );
	      $num_clustered++;
	      push( @$cell, "<span style='background-color: " . $cluster_colors->{ $peg_to_color->{ $peg } } . ";'>$peg_link</span>" );
	    }
	    else {
	      $num_unclustered++;
	      push @$cell, "<span>$peg_link</span>" ;
	    }
	  }
	  else {
	    push @$cell, $peg;
	  }
	}
	my $tt = $columnNameHash->{ $ind };
	push( @$new_row, { data => join( ',<br> ', @$cell ), tooltip => $tt } );
      }
      else {
	my $tt = $columnNameHash->{ $ind };
	push( @$new_row, { data => '', tooltip => $tt } );
      }
      $pattern .= $num_clustered.$num_unclustered.$cluster_num;
      if ( $num_clustered > 0 ) {
	$pat_num_clustered++;
      }
    }

    # pattern
    push(@$new_row, $pattern);
    # num_pattern
    push(@$new_row, $pat_num_clustered);

    # push row to table
    push(@$pretty_spreadsheet, $new_row);
  }

  ### create table from parsed data ###
  
  my $table = $self->application->component( 'SubsystemSpreadsheet' );
  $table->columns( $table_columns );
  $table->data( $pretty_spreadsheet );
  $table->show_top_browse( 1 );
  $table->show_select_items_per_page( 1 );
  $table->show_export_button( { strip_html => 1,
#				hide_invisible_columns => 1,
			        title      => 'Export plain data to Excel' } );

  ### remember some hidden values ###

  my $hiddenvalues = { 'filterOrganism' => '',
		       'sortOrganism'   => '',
		       'filterDomain'   => '',
		       'tableid'        => $table->id,
		       'showMoVariants' => $show_mo_variants };

  # finished
  return ( $legend, $legendg, $rolelist, $hiddenvalues, $emptycellshover );
}


sub get_scala_legend {
  my ( $max, $min, $text ) = @_;

  my $table = "<B>$text</B><BR>";
  $table .= "<TABLE><TR>\n";

  my $factor = ( $max - $min ) / 10;
  for( my $i = 0; $i <= 10; $i++ ) {

    my $val = int( ( $min + ( $factor * $i ) ) * 100 ) / 100;
    my $color = get_scalar_color( $val, $max, $min );
    $table .= "<TD STYLE='background-color: $color;'>$val</TD>\n";
 
  }
  $table .= "</TR></TABLE>";
  
  return $table;
}

sub get_value_legend {
  my ( $leghash, $text ) = @_;
  
  my $table = "<B>$text</B><BR>";
  $table .= "<DIV><TABLE STYLE='width: 800px;'><TR>\n";

  my $washere = 0;
  my $countcolor = 0;
  foreach my $k ( keys %$leghash ) {
    if ( ( $countcolor % 10 ) == 0 ) {
      $table .= "</TR><TR>";
    }
    my $color = $leghash->{ $k };
    $table .= "<TD STYLE='background-color: $color;'>$k</TD>\n";
    $washere = 1;
    $countcolor++;
  }
  
  $table .= "</TR></TABLE></DIV>";

  if ( $washere ) {
    return $table;
  }
  return undef;
}


sub collapse_groups {
  my ($self, $collapse_groups) = @_;
  
  if (defined($collapse_groups)) {
    $self->{collapse_groups} = $collapse_groups;
  }

  return $self->{collapse_groups};
}

#######################################
# List of attributes that are scalars #
#######################################
sub is_scala_attribute {

  my ( $attr ) = @_;
  
  if ( $attr eq 'isoelectric_point' 
       || $attr eq 'molecular_weight'
       || $attr eq 'Width'
       || $attr eq 'GC_Content'
       || $attr eq 'Doubling_Time_Mins'
       || $attr eq 'Temperature' ) {
    return 1;
  }
  return 0;

}

#####################################################
# List of attributes that are not used for coloring #
#####################################################
sub attribute_blacklist {

  my $list = { 'pfam-domain' => 1,
	       'PFAM'        => 1,
	       'CDD'         => 1 };
  return $list;

}

###########################
# Color for scalar values #
###########################
sub get_scalar_color {
  my ( $val, $max, $min ) = @_;

  return 0 if ( $max <= $min );

  my $r;
  my $g;
  my $b = 255;
  
  my $factor = 200 / ($max - $min);
  my $colval = $factor * ($val - $min);

  $r = int( 240 - $colval );
  $g = int( 240 - $colval );
  
  my $color = "rgb($r, $g, $b)";

  return $color;
}


######################################
# Panel for coloring the spreadsheet #
######################################
sub color_spreadsheet_panel {

  my ( $self, $preferences, $subsystem_name ) = @_;

  my $content = "<H2>Color genes in spreadsheet</H2>";

  my $default_coloring = $self->{ 'cgi' }->param( 'color_stuff' ) || 'do not color';

  if ( !defined( $self->{ 'cgi' }->param( 'color_by_peg_tag' ) ) && defined( $preferences->{ $subsystem_name."_color_by_peg_tag" } ) ) {
    $self->{ 'cgi' }->param( 'color_by_peg_tag', $preferences->{ $subsystem_name."_color_by_peg_tag" }->value );
  }

  my $defaultg_coloring = 'do not color';
  if ( defined( $self->{ 'cgi' }->param( 'colorg_stuff' ) ) ) {
    $defaultg_coloring = $self->{ 'cgi' }->param( 'colorg_stuff' );
  }

  my @color_opt = $self->{ 'cgi' }->radio_group( -name     => 'color_stuff',
				     -values   => [ 'do not color', 'by cluster', 'by FIGfams', 'by inconsistencies', 'by attribute: ' ],
				     -default  => $default_coloring,
				     -override => 1
				   );

  my @pegkeys = $self->{ 'fig' }->get_peg_keys();
  push @pegkeys, 'Expert_Annotations';

  #  Compile and order the attribute keys found on pegs:
  my $high_priority = qr/(essential|fitness)/i;
  my @options = sort { $b =~ /$high_priority/o <=> $a =~ /$high_priority/o
		      || uc( $a ) cmp uc( $b )
                    }
    @pegkeys;

  my $blacklist = attribute_blacklist();

  @options = grep { !$blacklist->{ $_ } } @options;
  unshift @options, undef;  # Start list with empty

  my $att_popup = $self->{ 'cgi' }->popup_menu(-name => 'color_by_peg_tag', -values => \@options);

  $content .= join( "<BR>\n", @color_opt );
  $content .= $att_popup;

  $content .= "<H2>Color genomes in spreadsheet</H2>";

  my @goptions = sort { uc( $a ) cmp uc( $b ) } $self->{ 'fig' }->get_genome_keys(); # get all the genome keys
  unshift @goptions, undef; # a blank field at the start

  my @colorg_opt = $self->{ 'cgi' }->radio_group( -name     => 'colorg_stuff',
				      -values   => [ 'do not color', 'by attribute: ' ],
				      -default  => $defaultg_coloring,
				      -override => 1
				    );
  
  my $genome_popup = $self->{ 'cgi' }->popup_menu( -name => 'color_by_ga', -values => \@goptions );
  $content .= join( "<BR>\n", @colorg_opt );
  $content .= $genome_popup;
  if ( $self->{ 'can_alter' } ) {
    $content .= "<BR><BR><INPUT TYPE=BUTTON VALUE='Color Spreadsheet' ONCLICK='SubmitSpreadsheet( \"Color Spreadsheet\", 2 );'>";
  }
  else {
    $content .= "<BR><BR><INPUT TYPE=BUTTON VALUE='Color Spreadsheet' ONCLICK='SubmitSpreadsheet( \"Color Spreadsheet\", 0 );'>";
  }

  return $content;
}

sub variant_panel {
  my ( $self, $subsystem, $name ) = @_;
  my $esc_name = uri_escape($name);

  my $variants = $subsystem->get_variants();

  my $vartable = $self->application->component( 'VarDescTable' );
  $vartable->columns( [ { name => "Variant" }, { name => "Description" } ] );
  
  my $vardata;
  my $has_variants = 0;
  foreach my $kv ( sort keys %$variants ) {
    $has_variants = 1;
    push @$vardata, [ $kv, $variants->{ $kv } ];
  }
  $vartable->data( $vardata );

  my $panel = '';
  if ( $has_variants ) {
    $panel .= $vartable->output();  
  }
  
  if ( $self->{ 'can_alter' } ) {
    my $variant_outside = "<INPUT TYPE=BUTTON VALUE='Edit Variants in Variant Overview' NAME='EditVariantsOverview' ID='EditVariantsOverview' ONCLICK='window.open( \"".$self->application->url()."?page=ShowVariants&subsystem=$esc_name\" )'>";
    $panel .= $variant_outside;
  }
  
  return $panel;
}

##################################
# Upper panel for adding genomes #
##################################
sub add_genomes_panel {

  my ( $self, $subsystem ) = @_;

  ####################################
  # collect some data into variables #
  ####################################
  # get a hash of all genomes of that subsystem #
  my %genomes = map { $_ => 1 } $subsystem->get_genomes();

  #################################
  # Put The New OrganismSelect in #
  #################################
  my $oselect = $self->application->component( 'OSelect' );
  $oselect->multiple( 1 );
  $oselect->width( 500 );
  $oselect->name( 'new_genome' );
  $oselect->blacklist( \%genomes );

  my @options = ( 'None',
  		   'Phage',
		   'Eukaryotic virus',
		   'NMPDR',
		   'BRC',
		   'Hundred by a hundred' );

  my @genomeListsUser = GenomeLists::getListsForUser();
  unshift @genomeListsUser, 'None';

  ###################
  # Build HTML here #
  ###################

  my $addgenomespanel .= "<TABLE><TR><TD><TABLE><TR><TD COLSPAN=4>";

  $addgenomespanel .= $oselect->output();

  $addgenomespanel .= "</TD></TR><TR><TD>";

  $addgenomespanel .= "<B>Specific Sets</B></TD><TD><B>User Sets</B></TD></TR><TR><TD>";

  # now special sets #
  $addgenomespanel .= $self->{ 'cgi' }->scrolling_list( -id      => 'add_special_set', 
					    -name    => 'add_special_set',
					    -values  => \@options,
					    -default => 'None',
					    -size => 4
					  );
  $addgenomespanel .= "</TD><TD><TABLE><TR><TD>\n";

  $addgenomespanel .= $self->{ 'cgi' }->scrolling_list( -id      => 'add_user_set', 
					    -name    => 'add_user_set',
					    -values  => \@genomeListsUser,
					    -default => 'None',
					    -size => 4
					  );
  $addgenomespanel .= "</TD><TD>\n";
  $addgenomespanel .= "<INPUT TYPE=BUTTON VALUE=\"Show selected\ngenome list\" ID='ShowSelectionButton' ONCLICK='OpenGenomeList( \"".$self->application->url()."\" );'>";
  $addgenomespanel .= "</TD></TR></TABLE></TD></TR></TABLE>\n";

  $addgenomespanel .= "</TD></TR><TR><TD>";

  $addgenomespanel .= "<INPUT TYPE=BUTTON VALUE='Add selected genome(s) to spreadsheet' ONCLICK='SubmitSpreadsheet( \"Add selected genome(s) to spreadsheet\", 0 );'>";

  $addgenomespanel .= "</TD></TR></TABLE><BR>";


  return $addgenomespanel;
}

##################################
# Upper panel for adding genomes #
##################################
sub add_region_panel {

  my ( $self, $subsystem ) = @_;

  #################################
  # Put The New OrganismSelect in #
  #################################
  my $rselect = $self->application->component( 'RSelect' );
  $rselect->multiple( 0 );
  $rselect->width( 500 );
  $rselect->name( 'new_region' );

  my $ajaxfucomponent = $self->application->component( 'Ajax' );

  ###################
  # Build HTML here #
  ###################

#  my $addgenomespanel .= "<TABLE><TR><TD COLSPAN=6>";

  my $addgenomespanel = $rselect->output();

  $addgenomespanel .= qq~<INPUT TYPE=BUTTON VALUE='Show Contigs' ONCLICK="execute_ajax( 'fill_contigs', 'REGIONCONTIGDIV', 'organism=' + document.getElementsByName( 'new_region' )[0].options[ document.getElementsByName( 'new_region' )[0].selectedIndex ].value );">~;
  $addgenomespanel .= $ajaxfucomponent->output();

  $addgenomespanel .= "<TABLE><TR><TD><INPUT TYPE='RADIO' name='region_location' value='Location:' CHECKED><B>Location:</B></TD><TD>";
  $addgenomespanel .= "<DIV ID=REGIONCONTIGDIV><TABLE><TR><TD>Contig:</TD><TD><SELECT NAME='RegionContig'></SELECT></DIV></TD>";
  $addgenomespanel .= "<TD>Start:</TD><TD><INPUT TYPE=TEXT NAME='RegionStart' SIZE=10></TD>";
  $addgenomespanel .= "<TD>Stop:</TD><TD><INPUT TYPE=TEXT NAME='RegionStop' ID='RegionStop' SIZE=10></TD></TR></TABLE></DIV></TD></TR>";

  $addgenomespanel .= "<TR><TD><INPUT TYPE='RADIO' name='region_location' value='Pegs-from-to:'><B>Pegs-from-to:</B><BR></TD><TD>";
  $addgenomespanel .= "<TABLE><TR><TD>Peg1:</TD><TD><INPUT TYPE=TEXT NAME='RegionPeg1' SIZE=10></TD>";
  $addgenomespanel .= "<TD>Peg2:</TD><TD><INPUT TYPE=TEXT NAME='RegionPeg2' SIZE=10></TD></TR>";

  $addgenomespanel .= "</TD></TR></TABLE><TR><TD>";

  $addgenomespanel .= "<INPUT TYPE=BUTTON VALUE='Add selected region' ONCLICK='SubmitSpreadsheet( \"Add selected region\", 1 );'>";

  $addgenomespanel .= "</TD></TR></TABLE><BR>";


  return $addgenomespanel;
}

sub fill_contigs {  
  my ( $self ) = @_;

  my $genome = $self->{ 'cgi' }->param( 'organism' );

  my $contig_lengths = $self->{ 'fig' }->contig_lengths( $genome );

  my $html = qq~<TABLE><TR><TD>Contig</TD><TD><SELECT NAME='RegionContig' onchange='document.getElementById( "RegionStop" ).value = this.options[ this.selectedIndex ].id;'>~;

  my $len = 0;
  foreach my $c ( sort keys %$contig_lengths ) {
    my $cid = $contig_lengths->{ $c };
    if ( $len == 0 ) {
      $len = $cid;
      $html .= "<OPTION ID='$cid' VALUE='$c' SELECTED=1>$c</OPTION>";
    }
    else {
      $html .= "<OPTION ID='$cid' VALUE='$c'>$c</OPTION>";
    }
  }

  $html .= "</SELECT></TD>";
  $html .= "<TD>Start:</TD><TD><INPUT TYPE=TEXT NAME='RegionStart' SIZE=10></TD>";
  $html .= "<TD>Stop:</TD><TD><INPUT TYPE=TEXT NAME='RegionStop' ID='RegionStop' SIZE=10 VALUE='$len'></TD></TR></TABLE>\n";

  return $html;
}


######################################
# Panel for coloring the spreadsheet #
######################################
sub limit_display_panel {
  
  my ( $self, $subsystem ) = @_;
  
  # create a new subsystem object #
  my @subsets = $subsystem->get_subset_namesC();

  my $default_activeSubsetR = $subsystem->get_active_subsetR;

  my @tmp = grep { $_ ne "All" } sort $subsystem->get_subset_namesR;
  
  my %options = ( "higher_plants"   => "Higher Plants",
		  "eukaryotic_ps"   => "Photosynthetic Eukaryotes",
		  "nonoxygenic_ps"  => "Anoxygenic Phototrophs",
		  "hundred_hundred" => "Hundred by a hundred",
		  "phage" => "Phage",
		  "euk_virus" => "Eukaryotic virus",
		  "functional_coupling_paper" => "Functional Coupling Paper",
		  "cyano_or_plant" => "Cyanos OR Plants",
		  "ecoli_essentiality_paper" => "E. coli Essentiality Paper",
		  "has_essentiality_data"	=> "Genomes with essentiality data",
		  "" =>  "All"
		);

  my @options = ( 'All',
		   "Phage",
		   'NMPDR',
		   'BRC',
		   'Hundred by a hundred',
		   "Eukaryotic virus",
		   );

  my @genomeListsUser = GenomeLists::getListsForUser();
  unshift @genomeListsUser, 'All';

  my @allsets = @subsets;
  my @starsets = grep { ( $_ =~ /^\*/ ) } @allsets;
  unshift @starsets, 'All';
  unshift @starsets, 'None';
    
  my $content .= "<P>Limit display of the the genomes in the table based on phylogeny or one of the preselected groups in the left box. Limit display of roles via their subsets and decide which subsets you want to uncollapse in the right box:<P>\n";
  
  # put in table #
  $content .= "<TABLE><TR><TD>";

  # build a little table for the genomes limiting
  $content .= "<DIV style=\"border-color: silver; border-style: solid; border-width: thick thin\"><H2>&nbsp; Limit displayed Genomes</H2><TABLE><TR><TD>";

  $content .= "<B>Phylogeny</B></TD><TD><B>Specific Sets</B></TD><TD><B>User Sets</B></TD></TR><TR><TD>";

  # phylogeny here #
  $content .= $self->{ 'cgi' }->scrolling_list( -id      => 'phylogeny_set',
				    -name    => 'phylogeny_set',
				    -values  => [ "All", @tmp ],
				    -default => 'All',
				    -size    => 5
				  );
  $content .= "</TD><TD>\n";

  # now special sets #
  $content .= $self->{ 'cgi' }->scrolling_list( -id      => 'special_set', 
				    -name    => 'special_set',
				    -values  => \@options,
				    -default => 'All',
				    -size => 5
				  );
  $content .= "</TD><TD>\n";

  # now special sets #
  $content .= $self->{ 'cgi' }->scrolling_list( -id      => 'user_set', 
				    -name    => 'user_set',
				    -values  => \@genomeListsUser,
				    -default => 'All',
				    -size => 5
				  );
  $content .= "</TD></TR></TABLE></DIV>\n";
  $content .= "</TD><TD>\n";

  ###############
  # Now Subsets #
  ###############

  # build a little table for the genomes limiting
  $content .= "<DIV style=\"border-color: silver; border-style: solid; border-width: thick thin\"><H2>&nbsp; Limit displayed Functional Roles &nbsp;</H2><TABLE><TR><TD>";

  $content .= "<B>Show Subsets<B></TD><TD><B>Uncollapse<B></TD></TR><TR><TD>";

  # now special sets #
  $content .= $self->{ 'cgi' }->scrolling_list( -id       => 'collection_set',
						-name     => 'collection_set',
						-multiple  => 1,
						-values   => \@allsets,
						-default  => [ 'All' ],
						-size     => 5
					      );
  $content .= "</TD><TD>\n";
  
  # now special sets #
  $content .= $self->{ 'cgi' }->scrolling_list( -id       => 'uncollapse_set', 
						-name     => 'uncollapse_set',
						-multiple => 1,
						-values   => \@starsets,
						-default  => [ 'None' ],
						-size     => 5
					      );

  $content .= "</TD></TR></TABLE></DIV>\n";
  $content .= "</TD></TR>\n</TABLE>";

  if ( $self->{ 'can_alter' } ) {
    $content .= "<BR><BR><INPUT TYPE=BUTTON VALUE='Limit Display' ONCLICK='SubmitSpreadsheet( \"LimitDisplay\", 3 );'>";
  }
  else {
    $content .= "<BR><BR><INPUT TYPE=BUTTON VALUE='Limit Display' ONCLICK='SubmitSpreadsheet( \"LimitDisplay\", 1 );'>";
  }

  return $content;
}


#################################
# Buttons under the spreadsheet #
#################################
sub get_spreadsheet_buttons {

  my ( $self, $name, $columnselect, $oben ) = @_;

  my $esc_name = uri_escape($name);
  
  my $delete_button = "<INPUT TYPE=HIDDEN VALUE=0 NAME='DeleteGenomesHidden' ID='DeleteGenomesHidden'>";
  $delete_button .= "<INPUT TYPE=BUTTON VALUE='Delete selected genomes' NAME='DeleteGenomes' ID='DeleteGenomes' ONCLICK='if ( confirm( \"Do you really want to delete the selected genomes from the spreadsheet?\" ) ) { 
 document.getElementById( \"DeleteGenomesHidden\" ).value = 1;
SubmitSpreadsheet( \"DeleteGenomes\", 0 ); }'>";
  my $sims_reference = "<INPUT TYPE=BUTTON VALUE='Color by sims to reference genome (Evalue)' ID='ColorSimsButton' NAME='ColorSimsButton' ONCLICK='SubmitSpreadsheet( \"ColorSimsButton\", 0 );'>"; 
  my $pident_reference = "<INPUT TYPE=BUTTON VALUE='Color by sims to reference genome (Percent Identity)' ID='ColorPidentButton' NAME='ColorPidentButton' ONCLICK='SubmitSpreadsheet( \"ColorPidentButton\", 0 );'>"; 
  my $showonly_button = "<INPUT TYPE=BUTTON VALUE='Show only selected genomes' ID='ShowOnlyButton' NAME='ShowOnlyButton' ONCLICK='SubmitSpreadsheet( \"ShowOnlyButton\", 0 );'>";
  my $saveselection_button = "<INPUT TYPE=BUTTON VALUE='Save genome selection' ID='SaveSelectionButton' ONCLICK='OpenGenomeSelection( \"".$self->application->url()."\" );'>";
  my $refillselection_button = "<INPUT TYPE=BUTTON VALUE='Refill Selected Genomes' ID='RefillSelectionButton' ONCLICK='SubmitSpreadsheet( \"RefillSelectionButton\", 0 );'>";
  my $fillselection_button = "<INPUT TYPE=BUTTON VALUE='Fill Selected Genomes' ID='FillSelectionButton' ONCLICK='SubmitSpreadsheet( \"FillSelectionButton\", 0 );'>";
  my $minus1_variant_button = "<INPUT TYPE=BUTTON VALUE='Show -1 variants' NAME='MoVariants' ID='MoVariants' ONCLICK='SubmitSpreadsheet( \"MoVariants\", 0 );'>";
  my $minus1_variant_hide_button = "<INPUT TYPE=BUTTON VALUE='Hide -1 variants' NAME='HideMoVariants' ID='HideMoVariants' ONCLICK='SubmitSpreadsheet( \"HideMoVariants\", 0 );'>";
  my $variant_button = "<INPUT TYPE=BUTTON VALUE='Edit Variants in this table' NAME='EditVariants' ID='EditVariants' ONCLICK='MakeEditableVariants( \"".$self->application->component( 'SubsystemSpreadsheet' )->id()."\" );'>";
  my $variant_outside = "<INPUT TYPE=BUTTON VALUE='Variant Overview' NAME='EditVariantsOverview' ID='EditVariantsOverview' ONCLICK='window.open( \"".$self->application->url()."?page=ShowVariants&subsystem=$esc_name\" )'>";
  my $check_variants = "<INPUT TYPE=BUTTON VALUE='Check Variants' NAME='CheckVariants' ID='CheckVariants' ONCLICK='window.open( \"".$self->application->url()."?page=CheckVariants&subsystem=$esc_name\" )'>";
  my $save_variant_button = "<INPUT TYPE=BUTTON VALUE='Save Variants' NAME='SaveVariants' STYLE='display: none; background-color: red;' ID='SaveVariants' ONCLICK='SubmitSpreadsheet( \"SaveVariants\", 0 );'>";
  my $refillall_button = "<INPUT TYPE=BUTTON VALUE='Refill All Genomes' ID='RefillAllButton' ONCLICK='if ( confirm( \"Do you really want to refill all genomes in the spreadsheet?\" ) ) { 
SubmitSpreadsheet( \"RefillAllButton\", 0 ); }'>";
  my $fillall_button = "<INPUT TYPE=BUTTON VALUE='Fill All Genomes' ID='FillAllButton' ONCLICK='if ( confirm( \"Do you really want to fill all genomes in the spreadsheet?\" ) ) { 
SubmitSpreadsheet( \"FillAllButton\", 0 ); }'>";
  my $showmissingwithmatches_button = "<INPUT TYPE=BUTTON VALUE='Show missing with matches' ID='ShowMissingWithMatchesButton' ONCLICK='window.open( \"".$self->application->url()."?page=ShowMissingWithMatches&subsystem=$esc_name\" )'>";
  my $missingwithmatches_button = "<INPUT TYPE=BUTTON VALUE='Missing with matches Table' ID='MissingWithMatchesButton' ONCLICK='window.open( \"".$self->application->url()."?page=MissingWithMatches&subsystem=$esc_name\" )'>";
  my $showmissingwithmatchesgenomes_button = "<INPUT TYPE=BUTTON VALUE='Show missing with matches' ID='ShowMissingWithMatchesGenomesButton' ONCLICK='OpenMissingWithMatchesGenome( \"".$self->application->url()."\", \"$esc_name\", 0 );'>";
  my $missingwithmatchesgenomes_button = "<INPUT TYPE=BUTTON VALUE='Missing with matches Table' ID='MissingWithMatchesGenomesButton' ONCLICK='OpenMissingWithMatchesGenome( \"".$self->application->url()."\", \"$esc_name\", 1 );'>";
  my $showmissingwithmatchescolumn_button = "<INPUT TYPE=BUTTON VALUE='Show missing with matches for columns' ID='ShowMissingWithMatchesColumnsButton' ONCLICK='OpenMissingWithMatchesColumn( \"".$self->application->url()."\", \"$esc_name\", 0 );'>";
  my $missingwithmatchescolumn_button = "<INPUT TYPE=BUTTON VALUE='Missing with matches Table for columns' ID='MissingWithMatchesColumnsButton' ONCLICK='OpenMissingWithMatchesColumn( \"".$self->application->url()."\", \"$esc_name\", 1 );'>";
  my $showemptycellsbutton = "<INPUT TYPE=BUTTON VALUE='Edit empty cells' ID='SHOWEMPTYCELLS' NAME='SHOWEMPTYCELLS' ONCLICK='SubmitSpreadsheet( \"SHOWEMPTYCELLS\", 0 );'>";
  my $noshowemptycellsbutton = "<INPUT TYPE=BUTTON VALUE='Do not Edit empty cells' ID='NOSHOWEMPTYCELLS' NAME='NOSHOWEMPTYCELLS' ONCLICK='SubmitSpreadsheet( \"NOSHOWEMPTYCELLS\", 0 );'>";
  my $saveemptycellsbutton = "<INPUT TYPE=BUTTON VALUE='Save edit for empty cells' ID='SAVEEMPTYCELLS' NAME='SAVEEMPTYCELLS' STYLE='background-color: red;' ONCLICK='SubmitSpreadsheet( \"SAVEEMPTYCELLS\", 0 );'>";

  my $checkall    = "<INPUT TYPE=BUTTON name='CheckAll' value='Check All' onclick='checkAll( \"genome_checkbox\" )'>\n";
  my $checkfirst  = "<INPUT TYPE=BUTTON name='CheckFirst' value='Check First Half' onclick='checkFirst( \"genome_checkbox\" )'>\n";
  my $checksecond = "<INPUT TYPE=BUTTON name='CheckSecond' value='Check Second Half' onclick='checkSecond( \"genome_checkbox\" )'>\n";
  my $uncheckall  = "<INPUT TYPE=BUTTON name='UnCheckAll' value='Uncheck All' onclick='uncheckAll( \"genome_checkbox\" )'>\n";
  my $checkallvar  = "<INPUT TYPE=BUTTON name='CheckAllVar' value='Check All With Variant:' onclick='checkAllVar( \"genome_checkbox\" )'>\n";
  my $variantbox = "<INPUT TYPE=TEXT name='VarBox' id='VarBox' size=6>";

  my $showgenesincolumn .= "<INPUT TYPE=BUTTON VALUE=\"Show genes in column\" ID='ShowGICButton' ONCLICK='OpenGenesInColumn( \"".$self->application->url()."\", \"$esc_name\" );'>";
  my $resolveparalogs .= "<INPUT TYPE=BUTTON VALUE=\"Resolve Paralogs\" ID='ShowParButton' ONCLICK='OpenParalogyfier( \"".$self->application->url()."\", \"$esc_name\", \"".$self->{ 'seeduser' }."\" );'>";

  my $spreadsheetbuttons = "<DIV id='controlpanel'><H2>Actions</H2>\n";
  if ( $self->{ 'can_alter' } ) {
    $spreadsheetbuttons .= "<TABLE><TR><TD><B>Edit Variants:</B></TD><TD>$minus1_variant_button $minus1_variant_hide_button</TD><TD>$variant_button $save_variant_button</TD><TD>$variant_outside</TD><TD>$check_variants</TD></TR></TABLE><BR>";
    $spreadsheetbuttons .= "<TABLE><TR><TD><B>Selection:</B></TD><TD>$delete_button</TD><TD>$showonly_button</TD><TD>$saveselection_button</TD><TD></TD></TR><TR><TD></TD><TD>$refillselection_button</TD><TD>$fillselection_button</TD><TD>$showmissingwithmatchesgenomes_button</TD><TD>$missingwithmatchesgenomes_button</TD></TR><TR><TD></TD><TD COLSPAN=2>$sims_reference</TD><TD COLSPAN=2>$pident_reference</TD></TR></TABLE><BR>";
  }
  else {
    $spreadsheetbuttons .= "<TABLE><TR><TD><B>Edit Variants:</B></TD><TD>$minus1_variant_button $minus1_variant_hide_button</TD></TR></TABLE><BR>";
    $spreadsheetbuttons .= "<TABLE><TR><TD><B>Selection:</B></TD><TD>$showonly_button</TD></TR></TABLE><BR>";
  }
  $spreadsheetbuttons .= "<TABLE><TR><TD><B>Select:</B></TD><TD>$checkall</TD><TD>$checkfirst</TD><TD>$checksecond</TD><TD>$uncheckall</TD><TD>$checkallvar</TD><TD>$variantbox</TD></TR></TABLE><BR>";
  if ( $self->{ 'can_alter' } ) {
    $spreadsheetbuttons .= "<TABLE><TR><TD><B>All Genomes:</B></TD><TD>$refillall_button</TD><TD>$fillall_button</TD><TD>$showmissingwithmatches_button</TD><TD>$missingwithmatches_button</TD></TR></TABLE><BR>";
    $spreadsheetbuttons .= "<TABLE><TR><TD><B>Empty Cells:</B></TD>";

    if ( $self->{ 'cgi' }->param( 'SHOWEMPTYCELLS' ) ) {
      $spreadsheetbuttons .= "<TD>$noshowemptycellsbutton</TD><TD>$saveemptycellsbutton</TD>";
    }
    else {
      $spreadsheetbuttons .= "<TD>$showemptycellsbutton</TD>";
    }
    $spreadsheetbuttons .= "</TR></TABLE><BR>";
  }
  if ( $oben ) {
    $spreadsheetbuttons .= "<TABLE><TR><TD><B>Columns:</B></TD><TD>$columnselect</TD><TD>$showgenesincolumn</TD><TD>$resolveparalogs</TD>";
    if ( $self->{ 'can_alter' } ) {
      $spreadsheetbuttons .= "<TD>$showmissingwithmatchescolumn_button</TD><TD>$missingwithmatchescolumn_button</TD>";
    }
    $spreadsheetbuttons .= "</TR></TABLE>";
  }
  $spreadsheetbuttons .= "</DIV>";

  return $spreadsheetbuttons;
}

###################################
# get organism domains and labels # 
###################################
sub get_main_domains {
  my %maindomain = ( Archaea          => 'A',
		     Bacteria           => 'B',
		     Eukaryota          => 'E',
		     Plasmid            => 'P',
		     Virus              => 'V',
		     'Environm. Sample' => 'M',  # Metagenome
		     unknown            => 'U'
		   );
  
  my %label;
  foreach my $k ( keys %maindomain ) {
    $label{ $k } = "$k \[". $maindomain{ $k } .']';
  }

  return ( \%maindomain, \%label );
}

######################
# Save variant codes #
######################
sub save_variant_codes {
  my ( $self, $subsystem ) = @_;

  my @genomes = $subsystem->get_genomes();

  foreach my $g ( @genomes ) {
    my $gidx = $subsystem->get_genome_index( $g );
    my $variant = $self->{ 'cgi' }->param( "variant$g" );
    next if ( !defined( $variant ) );
    $subsystem->set_variant_code( $gidx, $variant );
  }
#  $subsystem->incr_version();
  $subsystem->db_sync();
  $subsystem->write_subsystem();

  return( '', '' );
}

##################################
# Add genomes to the spreadsheet #
##################################
sub add_refill_genomes {
  my ( $self, $subsystem, $genomes, $add, $fill ) = @_;
  
  my $comment = "";

  if ( $genomes eq 'All' ) {
    my @gs = $subsystem->get_genomes();
    $genomes = \@gs;
  }

  foreach my $genome ( @$genomes ) {
    my $rawgenome = $genome;
    my $loc;

    unless ( $self->{ 'fig' }->is_genome( $genome ) ) {
      $genome =~ /(\d+\.\d+)\:(.*)/;
      $rawgenome = $1;
      $loc = $2;
      next unless ( $self->{ 'fig' }->is_genome( $rawgenome ) );
    }

    if ( $add ) {
      my $idx = $subsystem->get_genome_index($genome);
      if ( defined( $idx ) ) {
	next;
      }
      
      $subsystem->add_genome( $genome );
    }
    foreach my $role ( $subsystem->get_roles() ) {
      if ( $fill ) {
	my @inpegs = $subsystem->get_pegs_from_cell( $genome, $role );
	next if ( @inpegs > 0 );
      }
      my @pegs = $self->{ 'fig' }->seqs_with_role( $role, "master", $rawgenome);
      @pegs = grep { $subsystem->in_genome( $genome, $_ ) } @pegs;
      my %tmppegs = map { $_ => 1 } @pegs;
      @pegs = keys %tmppegs;

      $subsystem->set_pegs_in_cell( $genome, $role, \@pegs);
    }

    if ( $add ) {
      $comment .= "Added Genome $genome to the Seed<BR>\n";
    }
    elsif ( $fill ) {
      $comment .= "Filled Genome $genome<BR>\n";
    }
    else {
      $comment .= "Refilled Genome $genome<BR>\n";
    }
  }

  if ( ( $genomes eq 'All' ) && ( $add ) ) {
    $comment = "Refilled all genomes<BR>\n";
  }

#  $subsystem->incr_version();
  $subsystem->db_sync();
  $subsystem->write_subsystem();

  return ( '', $comment );
}

#######################################
# Remove genomes from the spreadsheet #
#######################################
sub remove_genomes {
  my( $self, $subsystem, $genomes ) = @_;

  my $comment = '';

  if ( scalar( @$genomes ) == 0 ) {
    return "No genomes selected to delete<BR>\n";
  }

  foreach my $genm ( @$genomes ) {
    $genm =~ /^genome_checkbox_(\d+\.\d+.*)/;
    my $genome = $1;
    my $rawgenome = $genome;

    if ( $genome =~ /(\d+\.\d+)\:(.*)/ ) {
      $rawgenome = $1;
      my $loc = $2;
      my $genomename = $self->{ 'fig' }->genus_species( $rawgenome );
      $comment .= "Deleted region $genomename".": $loc ( $genome ) from the spreadsheet<BR>\n";
    }
    else {
      my $genomename = $self->{ 'fig' }->genus_species( $rawgenome );
      $comment .= "Deleted genome $genomename ( $genome ) from the spreadsheet<BR>\n";
    }

    $subsystem->remove_genome( $genome );
  }

#  $subsystem->incr_version();
  $subsystem->db_sync();
  $subsystem->write_subsystem();

  return $comment;
}

###############
# data method #
###############
sub get_subsystem_data {

  my ( $self, $subsystem, $name, $emptycellshover, $showemptycellsparam ) = @_;

  my $esc_name = uri_escape($name);

  if ( defined( $showemptycellsparam ) && $showemptycellsparam ) {
    $emptycellshover->add_menu( 'buttonmenu', [ qq~<a onclick="setValueForSpreadsheetButton( this.parentNode.name, '-' )">Mark as -</a>~, qq~<a onclick="setValueForSpreadsheetButton( this.parentNode.name, '+' )">Mark as +</a>~, qq~<a onclick="openSearchGeneWindow( '$esc_name', this.parentNode.name )">Find candidates</a>~ ], [ '', '', '' ] );
  }

  # initialize roles, subsets and spreadsheet
  my ( $subsets, $collections, $spreadsheet, $allpegs );

  ## get da roles ##
  my @roles;
  my @rs = $subsystem->get_roles();
  foreach my $r ( @rs ) {
    my $abb = $subsystem->get_abbr_for_role( $r );
    my $in = $subsystem->get_role_index( $r );
    push @roles, [ $abb, $r, $in ];
  }

  ## now get da subsets ##
  my @subsetArr = $subsystem->get_subset_names();
  foreach my $subsetname ( @subsetArr ) {
    next if ( $subsetname eq 'All' );
    my @things = $subsystem->get_subsetC( $subsetname );
    my @things2;
    foreach my $t ( @things ) {
      $t++;
      push @things2, $t;
    }
    if ( $subsetname =~ /^\*/ ) {
      $subsets->{ $subsetname } = \@things2;
    }
    $collections->{ $subsetname } = \@things2;
  }

  my @genomes = $subsystem->get_genomes();

  my $emptycells = $subsystem->get_emptycells();

  my %spreadsheethash;

  foreach my $genome ( @genomes ) {

    my $gidx = $subsystem->get_genome_index( $genome );
    my $loc = '';

    my $rawgenome = $genome;
    if ( $genome =~ /(\d+\.\d+)\:(.*)/ ) {
      $rawgenome = $1;
      $loc = ": $2";
    }

    $spreadsheethash{ $genome }->{ 'name' } = $self->{ 'fig' }->genus_species( $rawgenome ). $loc;
    $spreadsheethash{ $genome }->{ 'domain' } = $self->{ 'fig' }->genome_domain( $rawgenome );
    $spreadsheethash{ $genome }->{ 'taxonomy' } = $self->{ 'fig' }->taxonomy_of( $rawgenome );
    $spreadsheethash{ $genome }->{ 'variant' } = $subsystem->get_variant_code( $gidx );

    my $rowss = $subsystem->get_row( $gidx );
    my @row;
    #    my @row_onlypegs;
    
    my $c = 0;
    foreach my $tr ( @$rowss ) {
      if ( defined( $tr->[0] ) ) {
	push @$allpegs, @$tr;
	push @row, join( ', ', @$tr );
      }
      else {
	if ( defined( $showemptycellsparam ) && $showemptycellsparam ) {
	  my $sign = '?';
	  
	  my $thisrole = $subsystem->get_role_abbr( $c );

	  if ( defined( $emptycells->{ $thisrole } ) && defined( $emptycells->{ $thisrole }->{ $genome } ) ) {
	    $sign = $emptycells->{ $thisrole }->{ $genome };
	  }
	  my $tr2 = $thisrole.'##-##'.$genome;
	  my $tr2hidden = 'HIDDEN'.$tr2;
	  push @row, qq~<INPUT TYPE=BUTTON VALUE="$sign" NAME='EMPTYCELLBUTTONS' id='$tr2' onclick="hover(event,'buttonmenu','~.$emptycellshover->id.qq~' );"><INPUT TYPE=HIDDEN VALUE="$sign" NAME='EMPTYCELLHIDDENS' id='$tr2hidden'~;
	}
	else {
	  push @row, '';
	}
      }
      $c++;
    }
    
    $spreadsheethash{ $genome }->{ 'row' } = \@row;
  }

  # get all peg functions in bulk
  my $peg_functions = $self->{ 'fig' }->function_of_bulk( $allpegs );
  
  return ( \@roles, $subsets, $collections, \%spreadsheethash, $allpegs, $peg_functions );
  
}

sub get_groups_for_pegs {
  my ( $self, $attr, $pegs ) = @_;

  my %arr;

  # there is one attribute which is not on the attribute
  # server but relates to expert annotations im clearinghouse
  # this will be handled here
  if ( $attr eq 'Expert_Annotations' ) {
    my @assertions = &FIG::get_expert_assertions( $pegs );
    foreach my $a ( @assertions ) {
      push @{ $arr{ $a->[1] } }, $a->[0];
    }
  }
   elsif ( $attr eq 'figfams' ) {
     my $figfamsObject = new FFs( $self->{fig}->get_figfams_data(), $self->{ 'fig' } );

     for my $peg (@$pegs)
     {
	 my $fam = $figfamsObject->family_containing_peg($peg);
	 push(@{$arr{$fam}}, $peg);
     }
     #my $famhash = $figfamsObject->families_containing_peg_bulk( $pegs );
     #foreach my $p ( keys %$famhash ) {
     #  push @{ $arr{ $famhash->{ $p } } }, $p;
     #}
   }
  else {
    my @attribs = $self->{ 'fig' }->get_attributes( $pegs, $attr );
    
    foreach my $at ( @attribs ) {
      push @{ $arr{ $at->[2] } }, $at->[0];
    }
  }

  return \%arr;
}

sub get_groups_for_genomes {
  my ( $self, $attr, $genomes ) = @_;

  my @attribs = $self->{ 'fig' }->get_attributes( $genomes, $attr );

  my %arr;

  foreach my $at ( @attribs ) {
    push @{ $arr{ $at->[2] } }, $at->[0];
  }
  
  return \%arr;
}

sub get_color_by_attribute_infos {

  my ( $self, $attr, $pegsarr, $colors ) = @_; 

  my $scalacolor = is_scala_attribute( $attr );
  my $legend;
  my $peg_to_color_alround;
  my $cluster_colors_alround;
  
  if ( defined( $attr ) ) {
    my $groups_for_pegs = $self->get_groups_for_pegs( $attr, $pegsarr );
    my $i = 0;
    my $biggestitem = 0;
    my $smallestitem = 100000000000;
    
    if ( $scalacolor ) {
      foreach my $item ( keys %$groups_for_pegs ) {
	
	if ( $biggestitem < $item ) {
	  $biggestitem = $item;
	}
	if ( $smallestitem > $item ) {
	  $smallestitem = $item;
	}
      }
      $legend = get_scala_legend( $biggestitem, $smallestitem, 'Color legend for CDSs' );
    }
    
    my $leghash;
    foreach my $item ( keys %$groups_for_pegs ) {
      foreach my $peg ( @{ $groups_for_pegs->{ $item } } ) {
	$peg_to_color_alround->{ $peg } = $i;
      }
      
      if ( $scalacolor ) {
	my $col = get_scalar_color( $item, $biggestitem, $smallestitem );
	$cluster_colors_alround->{ $i } = $col;
      }
      else {
	$cluster_colors_alround->{ $i } = $colors->[ scalar( keys( %$cluster_colors_alround ) ) ];
	$leghash->{ $item } = $cluster_colors_alround->{ $i };
      }
      $i++;
    }
    if ( !$scalacolor ) {
      $legend = get_value_legend( $leghash, 'Color Legend for CDSs' );
    }
  }
  return ( $peg_to_color_alround, $cluster_colors_alround, $legend );
}


sub get_color_by_sims {
  my ( $self, $pegsarr, $colors, $spreadsheethash, $what ) = @_;

  my $genome = $self->{ 'colorsimsgenome' };
  if ( $what eq 'pident' ) {
    $genome = $self->{ 'colorpidentgenome' };
  }

  
  my $thisrow = $spreadsheethash->{ $genome }->{ 'row' };
  my @row = @$thisrow;

  my $referencehash;
  my $colorhash;

  my $peg_to_color_alround;
  my $cluster_colors_alround;

  my $evalue_ranges;
  if ( $what eq 'evalue' ) {
    $evalue_ranges = ["< 1e-170", "1e-170 -<BR> 1e-120", "1e-120 -<BR> 1e-90",
		      "1e-90 -<BR> 1e-70", "1e-70 -<BR> 1e-40",
		      "1e-40 -<BR> 1e-20", "1e-20 -<BR> 1e-5",
		      "1e-5 -<BR> 1", "1 -<BR> 10", ">10"];
  }
  else {
    $evalue_ranges = ["100", "100 -<BR> 90",
		      "90 -<BR> 80", "80 -<BR> 70",
		      "70 -<BR> 60", "60 -<BR> 50",
		      "50 -<BR> 40", "40 -<BR> 30",
		      "30 -<BR> 20", "20 -<BR> 10" ];
  }
    
  my $parameters = { 'flag' => 1, 'max_sims' => 5000, 'max_expand' => 500,
		     'max_evalue' => 0.01, 'db_filter' => 'fig',
		     'sim_order' => 'id', 'group_genome' => 0
		   };
  
  my $leghash;
  my $legend;
  my $palette = WebColors::get_palette( 'vitamins' );

  $legend .= "<DIV><TABLE STYLE='width: 800px;'><TR>\n";

  for ( my $a = 0; $a < 10; $a++ ) {
    $legend .= "<TD STYLE='background-color: rgb(".join( ', ', @{ $palette->[ $a ] } ).");'>".$evalue_ranges->[ $a ]."</TD>\n";
    $cluster_colors_alround->{ $a } = "rgb(".join( ', ', @{ $palette->[ $a ] } ).")";
  }

  $legend .= "</TR></TABLE></DIV>";

  foreach my $pegs ( @row ) {
    
    my @pegsincell = split( /, /, $pegs );
    next if ( scalar( @pegsincell < 1 ) );

    my $p = $pegsincell[0];

#    my @pegs = map {$_->[1]} $fig->sims($peg, 10000, $sim_cutoff, "fig");
    my $array = Observation->get_sims_objects( $p, $self->{ 'fig' },$parameters);

    foreach my $thing ( @$array ) {
      next if ( $thing->class ne "SIM" );
      my $hit_peg = $thing->acc;
      my $eval = $thing->evalue;
      my $ident = $thing->identity;

      if ( $what eq 'evalue' ) {
	if ( $eval < 1e-170 ) {
	  $peg_to_color_alround->{ $hit_peg } = 0;
	}
	elsif ( $eval < 1e-120 ) {
	  $peg_to_color_alround->{ $hit_peg } = 1;
	}
	elsif ( $eval < 1e-90 ) {
	  $peg_to_color_alround->{ $hit_peg } = 2;
	}
	elsif ( $eval < 1e-70 ) {
	  $peg_to_color_alround->{ $hit_peg } = 3;
	}
	elsif ( $eval < 1e-40 ) {
	  $peg_to_color_alround->{ $hit_peg } = 4;
	}
	elsif ( $eval < 1e-20 ) {
	  $peg_to_color_alround->{ $hit_peg } = 5;
	}
	elsif ( $eval < 1e-5 ) {
	  $peg_to_color_alround->{ $hit_peg } = 6;
	}
	elsif ( $eval < 1 ) {
	  $peg_to_color_alround->{ $hit_peg } = 7;
	}
	else {
	  $peg_to_color_alround->{ $hit_peg } = 8;
	}
      }
      else {
	if ( $ident == 100  ) {
	  $peg_to_color_alround->{ $hit_peg } = 0;
	}
	elsif ( $ident > 90 ) {
	  $peg_to_color_alround->{ $hit_peg } = 1;
	}
	elsif ( $ident > 80 ) {
	  $peg_to_color_alround->{ $hit_peg } = 2;
	}
	elsif ( $ident > 70 ) {
	  $peg_to_color_alround->{ $hit_peg } = 3;
	}
	elsif ( $ident > 60 ) {
	  $peg_to_color_alround->{ $hit_peg } = 4;
	}
	elsif ( $ident > 50 ) {
	  $peg_to_color_alround->{ $hit_peg } = 5;
	}
	elsif ( $ident > 40 ) {
	  $peg_to_color_alround->{ $hit_peg } = 6;
	}
	elsif ( $ident > 30 ) {
	  $peg_to_color_alround->{ $hit_peg } = 7;
	}
	elsif ( $ident > 20 ) {
	  $peg_to_color_alround->{ $hit_peg } = 8;
	}
	elsif ( $ident > 10 ) {
	  $peg_to_color_alround->{ $hit_peg } = 9;
	}
      }
    }
  }
  if ( $what eq 'pident' ) {
    $legend = "<B>SIMS against ". $self->{ 'fig' }->genus_species( $self->{ 'colorpidentgenome' } ).'( '.$self->{ 'colorpidentgenome' }. ")</B><BR><BR>" . $legend;
  }
  else {     
    $legend = "<B>SIMS against ". $self->{ 'fig' }->genus_species( $self->{ 'colorsimsgenome' } ).'( '.$self->{ 'colorsimsgenome' }. ")</B><BR><BR>" . $legend;
  }

  return ( $peg_to_color_alround, $cluster_colors_alround, $legend );
}  

sub get_color_by_check {
  my ( $self, $peg_functions, $colors, $spreadsheethash, $subsystem ) = @_;
  
  my $referencehash;
  my $colorhash;
  
  my $peg_to_color_alround;
  my $cluster_colors_alround;
  my $i = 0;
  $cluster_colors_alround->{ $i } = "rgb(240, 240, 240)";
  $i++;
  $cluster_colors_alround->{ $i } = "rgb(255, 100, 100)";
  
  my $leghash;
  my $legend;
  
  foreach my $g ( keys %$spreadsheethash ) {
    my $c = 0;
    my $row = $spreadsheethash->{ $g }->{ 'row' };
    foreach my $pegs ( @$row ) {
      my $thisrole = $subsystem->get_role( $c );
      
      my @pegsincell = split( /, /, $pegs );
      foreach my $p ( @pegsincell ) {
	$peg_to_color_alround->{ $p } = 0;
	unless ( $peg_functions->{ $p } =~ /$thisrole/ ) {
	  $peg_to_color_alround->{ $p } = 1;
	}
      }
      $c++
    }
  }

  return ( $peg_to_color_alround, $cluster_colors_alround, $legend );
}  

sub get_color_by_attribute_infos_for_genomes {
  
  my ( $self, $spreadsheethash, $colors ) = @_; 
  
  my $genomes_to_color;
  my $genome_colors;
  my $legend;
  my $leghash;
  my $i = 0;
  my $biggestitem = 0;
  my $smallestitem = 100000000000;
  
  my $attr = $self->{ 'cgi' }->param( 'color_by_ga' );
  my $scalacolor = is_scala_attribute( $attr );
  
  my @genomes = keys %$spreadsheethash;
  my $groups_for_genomes = $self->get_groups_for_pegs( $attr, \@genomes );

  if ( $scalacolor ) {
    
    foreach my $item ( keys %$groups_for_genomes ) {
      
      if ( $biggestitem < $item ) {
	$biggestitem = $item;
      }
      if ( $smallestitem > $item ) {
	$smallestitem = $item;
      }
    }
    $legend = get_scala_legend( $biggestitem, $smallestitem, 'Color Legend for Genomes' );
  }
  
  foreach my $item ( keys %$groups_for_genomes ) {
    foreach my $g ( @{ $groups_for_genomes->{ $item } } ) {
      $genomes_to_color->{ $g } = $i;
    }
    
    if ( $scalacolor ) {
      my $col = get_scalar_color( $item, $biggestitem, $smallestitem );
      $genome_colors->{ $i } = $col;
    }
    else {
      $genome_colors->{ $i } = $colors->[ scalar( keys( %$genome_colors ) ) ];
      $leghash->{ $item } = $genome_colors->{ $i };
    } 
    $i++;
  }
  if ( !$scalacolor ) {
    $legend = get_value_legend( $leghash, 'Color Legend for Genomes' );
  }

  return ( $genomes_to_color, $genome_colors, $legend );
}

sub get_colors {
  my ( $self ) = @_;

  return [ '#d94242', '#eaec19', '#715ae5', '#25d729', '#f9ae1d', '#19b5b3', '#b519b3', '#ffa6ef',
	   '#744747', '#701414', '#70a444', '#C0C0C0', '#FF40C0', '#FF8040', '#FF0080', '#FFC040', 
	   '#40C0FF', '#40FFC0', '#C08080', '#C0FF00', '#00FF80', '#00C040',
	   "#6B8E23", "#483D8B", "#2E8B57", "#008000", "#006400", "#800000", "#00FF00", "#7FFFD4",
	   "#87CEEB", "#A9A9A9", "#90EE90", "#D2B48C", "#8DBC8F", "#D2691E", "#87CEFA", "#E9967A", 
	   "#FFE4C4", "#FFB6C1", "#E0FFFF", "#FFA07A", "#DB7093", "#9370DB", "#008B8B", "#FFDEAD",
	   "#DA70D6", "#DCDCDC", "#FF00FF", "#6A5ACD", "#00FA9A", "#228B22", "#1E90FF", "#FA8072", 
	   "#CD853F", "#DC143C", "#FF6347", "#98FB98", "#4682B4", "#D3D3D3", "#7B68EE", "#2F4F4F", 
	   "#FF7F50", "#FF69B4", "#BC8F8F", "#A0522D", "#DEB887", "#00DED1", "#6495ED", "#800080", 
	   "#FFD700", "#F5DEB3", "#66CDAA", "#FF4500", "#4B0082", "#CD5C5C", "#EE82EE", "#7CFC00", 
	   "#FFFF00", "#191970", "#FFFFE0", "#DDA0DD", "#00BFFF", "#DAA520", "#008080", "#00FF7F",
	   "#9400D3", "#BA55D3", "#D8BFD8", "#8B4513", "#3CB371", "#00008B", "#5F9EA0", "#4169E1",
	   "#20B2AA", "#8A2BE2", "#ADFF2F", "#556B2F", "#F0FFFF", "#B0E0E6", "#FF1493", "#B8860B",
	   "#FF0000", "#F08080", "#7FFF00", "#8B0000", "#40E0D0", "#0000CD", "#48D1CC", "#8B008B", 
	   "#696969", "#AFEEEE", "#FF8C00", "#EEE8AA", "#A52A2A", "#FFE4B5", "#B0C4DE", "#FAF0E6", 
	   "#9ACD32", "#B22222", "#FAFAD2", "#808080", "#0000FF", "#000080", "#32CD32", "#FFFACD", 
	   "#9932CC", "#FFA500", "#F0E68C", "#E6E6FA", "#F4A460", "#C71585", "#BDB76B", "#00FFFF", 
	   "#FFDAB9", "#ADD8E6", "#778899" ];
}

sub getActiveSubsetHash {

  my ( $self, $subsystem, $subsystemactive, $andor ) = @_;

  my $activeR;
  if ( !defined( $andor ) ) {
    $andor = 1;
  }
  my $evaluate = 0;

  my $phylo = $self->{ 'cgi' }->param( 'phylogeny_set' );
  my $special = $self->{ 'cgi' }->param( 'special_set' );
  my $userset = $self->{ 'cgi' }->param( 'user_set' );

  if ( $subsystemactive ) {
    my $activeKey = $subsystem->get_active_subsetR;
    my @subsetR = $subsystem->get_subsetR( $activeKey );
    my %activeRH = map { $_ => 1 } @subsetR;
    $activeR = \%activeRH;
  }
  else {
    if ( defined( $special ) && $special ne '' && $special ne 'All' ) {
      my @subsetspecial = moregenomes( $self, $special );
      my %activeRH = map { $_ => 1 } @subsetspecial;
      $activeR = \%activeRH;
      $evaluate = 1;
    }
    if ( defined( $phylo ) && $phylo ne '' && $phylo ne 'All' ) {
      my @subsetR = $subsystem->get_subsetR( $phylo );
      my %activeRH = map { $_ => 1 } @subsetR;  

      if ( $evaluate ) {
	$activeR = andor( $activeR, \%activeRH, $andor );
      }
      else {
	$activeR = \%activeRH;
      }
      $evaluate = 1;
    }
    if ( defined( $userset ) && $userset ne '' && $userset ne 'All' ) {
      my %activeRH;
      my $gl = GenomeLists::load( $userset );
      if (ref($gl))
      {
	  my $gs = $gl->{ 'genomes' };
	  foreach my $ssu ( @$gs ) {
	      $activeRH{ $ssu } = 1;
	  }
	  if ( $evaluate ) {
	      $activeR = andor( $activeR, \%activeRH, $andor );
	  }
	  else {
	      $activeR = \%activeRH;
	  }
      }
    }
  }

  return $activeR;
}

sub andor {
  my ( $h1, $h2, $andor ) = @_;
  
  if ( !$andor ) {
    foreach my $k ( keys %$h2 ) {
      $h1->{ $k } = $h2->{ $k };
    }
    return $h1;
  }
  my $h3;
  foreach my $k ( keys %$h1 ) {
    if ( defined( $h2->{ $k } ) ) {
      $h3->{ $k } = 1;
    }
  }
  return $h3;
}

sub get_userlist_hash {
  my ( $usersetlist, $ghash ) = @_;
  
  my $gl = GenomeLists::load( $usersetlist );
  my $gs = $gl->{ 'genomes' };
  foreach my $ssu ( @$gs ) {
    $ghash->{ $ssu } = 1;
  }
  return $ghash;
}


sub setCGIParameter {

  my ( $self, $user, $name, $paramname, $preferences, $isarray ) = @_;

  my $esc_name = uri_escape($name);

  my $p;

  if ( defined( $self->{ 'cgi' }->param( $paramname ) ) ) {
    if ( $isarray ) {
      my @pp = $self->{ 'cgi' }->param( $paramname );
      $p = join( ',##,', @pp );
    }
    else {
      $p = $self->{ 'cgi' }->param( $paramname );
    }
    unless ( $preferences->{ $esc_name."_".$paramname } ) {
      if ( defined( $user ) && ref( $user ) ) {
	$preferences->{ $esc_name."_".$paramname } = $self->application->dbmaster->Preferences->create( { user        => $user,
												      application => $self->application->backend,
												      name        => $esc_name."_".$paramname,
												      value       => $p } );
      }
    }
    else {
      $preferences->{ $esc_name."_".$paramname }->value( $p );
    }
  }
  elsif ( $preferences->{ $esc_name."_".$paramname } ) {
    if ( $isarray ) {
      $self->{ 'cgi' }->param( $paramname, split( ',##,', $preferences->{ $esc_name."_".$paramname }->value ) );
    }
    else {
      $self->{ 'cgi' }->param( $paramname, $preferences->{ $esc_name."_".$paramname }->value );
    }
  }
}
