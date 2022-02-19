package SubsystemEditor::WebPage::MetaSpreadsheet;

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

  $self->application->register_component( 'Table', 'SubsystemSpreadsheet' );
  $self->application->register_component( 'TabView', 'functionTabView' );
  $self->application->register_component( 'Info', 'CommentInfo');
  $self->application->register_component( 'OrganismSelect', 'OSelect');
  $self->application->register_component( 'Table', 'LD_SUBSETS' );
  $self->application->register_component( 'Table', 'LD_ROLES' );
  $self->application->register_component( 'Table', 'FunctionalRolesTable'  );

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
  $self->{ 'cgi' } = $self->application->cgi;
  
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
  my $seeduser = '';


  $self->{ 'metasubsystem' } = new MetaSubsystem( $name, $self->{ 'fig' }, 0 );

  if ( defined( $preferences->{ 'SeedUser' } ) ) {
    $seeduser = $preferences->{ 'SeedUser' }->value;
  }
  if ( $user ) {
    if ( $user->has_right( $self->application, 'edit', 'metasubsystem', $esc_name ) ) {
      $self->{ 'can_alter' } = 1;
      $self->{ 'fig' }->set_user( $seeduser );
      $self->{ 'seeduser' } = $seeduser;
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
	  $self->{ 'seeduser' } = $seeduser;
	}
      }
    }
  }

  my ( $phylo, $row_ss_members ) = $self->get_phylo_groups();
  $self->{ 'row_subset_members' } = $row_ss_members;

  #########
  # TASKS #
  #########

  my ( $error, $comment ) = ( "", "" );
  if ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'LimitSubsets' ) {
    
    my @showsets = $self->{ 'cgi' }->param( 'show_set' );
    my @collapsesets = $self->{ 'cgi' }->param( 'collapse_set' );
    my @showrole = $self->{ 'cgi' }->param( 'show_role' );
    
    my $view;
    
    foreach my $set ( @showsets ) {
      $set =~ /show_set_(.*)/;
      $view->{ 'Subsets' }->{ $1 }->{ 'visible' } = 1;
    }
    foreach my $set ( @collapsesets ) {
      $set =~ /collapse_set_(.*)/;
      $view->{ 'Subsets' }->{ $1 }->{ 'collapsed' } = 1;
    }
    foreach my $role ( @showrole ) {
      $role =~ /show_role_(.*)\##-##(.*)/;
      my $tmprole = $1.'##-##'.$2;
      $view->{ 'Roles' }->{ $tmprole }->{ 'visible' } = 1;
      $view->{ 'Roles' }->{ $tmprole }->{ 'subsystem' } = $2;
    }
    $self->{ 'metasubsystem' }->{ 'view' } = $view;
    $self->{ 'metasubsystem' }->write_metasubsystem();
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'PLUSMINUS' ) {
    $self->{ 'plusminus' } = 1;
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'NOTPLUSMINUS' ) {
    $self->{ 'plusminus' } = 0;
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'DeleteGenomes' ) {
    my @genomesIds = $self->{ 'cgi' }->param( 'genome_checkbox' );
    my ( $putcomment ) = $self->remove_genomes( \@genomesIds );
    $comment .= $putcomment;
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'Add selected genome(s) to spreadsheet' ) {
    my @newGenomes = $self->{ 'cgi' }->param( 'new_genome' );
    my $specialsetlist = $self->{ 'cgi' }->param( 'add_special_set' );
    my $usersetlist = $self->{ 'cgi' }->param( 'add_user_set' );
    my $ghash = {};
    unless( $specialsetlist eq 'None' ) {
      my @subsetspecial = $self->moregenomes( $specialsetlist );
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
    
    my ( $puterror, $putcomment ) = $self->add_refill_genomes( $ghash );
    $error .= $puterror;
    $comment .= $putcomment;
  }
  if ( !defined( $self->{ 'activeSubsetHash' } ) ) {
    $self->{ 'activeSubsetHash' } = $self->getActiveSubsetHash();
  }
  
  $self->get_metass_data();
  
  ########
  # Data #
  ########
  
  my ( $hiddenvalues ) = $self->load_subsystem_spreadsheet( $application, $preferences );
  
  my $table = $self->application->component( 'SubsystemSpreadsheet' );
  my $frtable = $self->application->component( 'FunctionalRolesTable' );
  
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

  # colorpanel #
  my $colorpanel = $self->color_spreadsheet_panel( $preferences, $name );
  # limitdisplaypanel #
  my $limitdisplaypanel = $self->limit_display_panel();
  my $limitsubsetspanel = $self->limit_subsets_panel();
  # addgenomespanel #
  my $addgenomepanel = $self->add_genomes_panel( $application );

  # spreadsheetbuttons #
  my $spreadsheetbuttons = $self->get_spreadsheet_buttons();

  my $tab_view_component = $self->application->component( 'functionTabView' );
  $tab_view_component->width( 900 );
  if ( $self->{ 'can_alter' } ) {
    $tab_view_component->add_tab( '<H2>&nbsp; Add Genomes to Spreadsheet &nbsp;</H2>', "$addgenomepanel" );
  }
  $tab_view_component->add_tab( '<H2>&nbsp; Color Spreadsheet &nbsp;</H2>', "$colorpanel" );
  $tab_view_component->add_tab( '<H2>&nbsp; Limit Genomes &nbsp;</H2>', "$limitdisplaypanel" );
  $tab_view_component->add_tab( '<H2>&nbsp; Limit Subsets &nbsp;</H2>', "$limitsubsetspanel" );
  $tab_view_component->add_tab( '<H2>&nbsp; Functional Roles &nbsp;</H2>', $frtable->output() );
  #  $tab_view_component->add_tab( '<H2>&nbsp; Show Variants &nbsp;</H2>', "$variantpanel" );
  
  if ( defined( $self->{ 'cgi' }->param( 'defaulttabhidden' ) ) ) {
    $tab_view_component->default( $self->{ 'cgi' }->param( 'defaulttabhidden' ) );
  }
  else {
    $tab_view_component->default( 0 );
  }

  # add hidden parameter for the tab that is actually open #
  my $dth = 0;
  if ( defined( $self->{ 'cgi' }->param( 'defaulttabhidden' ) ) ) {
    $dth = $self->{ 'cgi' }->param( 'defaulttabhidden' );
  }

  $hiddenvalues->{ 'metasubsystem' } = $name;
  $hiddenvalues->{ 'buttonpressed' } = 'none';
  $hiddenvalues->{ 'defaulttabhidden' } = $dth;
  $hiddenvalues->{ 'PLUSMINUS' } = $self->{ 'plusminus' };

  ###########
  # Content #
  ###########

  my $content = "<H1>Subsystem Metaview for $ssname</H1>";

  if ( defined( $comment ) && $comment ne '' ) {
    my $info_component = $application->component( 'CommentInfo' );

    $info_component->content( $comment );
    $info_component->default( 0 );
    $content .= $info_component->output();
  }    

  # start form #
  $content .= $self->start_form( 'subsys_spreadsheet', $hiddenvalues );
  $content .= "<TABLE><TR><TD>";

  $content .= $tab_view_component->output();
  $content .= "</TD></TR><TR><TD>";
  # put in color legends #
  if ( defined( $self->{ 'legend' } ) ) {
    $content .= $self->{ 'legend' };
    $content .= "</TD></TR><TR><TD>";
  }
  if ( defined( $self->{ 'legendg' } ) ) {
    $content .= $self->{ 'legendg' };
    $content .= "</TD></TR><TR><TD>";
  }

  $content .= $spreadsheetbuttons;
  $content .= "</TD></TR><TR><TD>";
  $content .= $table->output();
  $content .= "</TD></TR><TR><TD>";
  $content .= $spreadsheetbuttons;

  $content .= "</TD></TR>";
  $content .= "</TABLE>";

  # end form 
  $content .= $self->end_form();
  
  return $content;
}

##############################
# draw subsystem spreadsheet #
##############################
sub load_subsystem_spreadsheet {
  my ( $self, $application, $preferences ) = @_;

  # initialize roles, subsets and spreadsheet
  my $roles = $self->{ 'data_roles' };
  my $subsets = $self->{ 'data_subsets' };
  my $spreadsheet_hash = $self->{ 'data_spreadsheethash' };
  my $pegsarr = $self->{ 'data_allpegs' };

  my $user = $application->session->user();
  my $seeduser = $self->{ 'seeduser' };
  my $metass = $self->{ 'metasubsystem' };


  # get a list of sane colors
  my $colors = $self->get_colors();

  #####################################
  # Displaying and Collapsing Subsets #
  #####################################

  # Now - what roles or what subsets do I take?
  my $role_to_group;
  my $columns;
  my $visible;
  my $role_to_function;
  my $function_to_role;
  my $subsetssupercolumns = 0;
  my $roletosubsethidden;

  my $th = $metass->{ 'view' }->{ 'Roles' };

  foreach my $subset ( sort keys %$subsets ) {
    foreach my $abb ( keys %{ $subsets->{ $subset } } ) {
      push @{ $role_to_group->{ $abb } }, $subset;
      $roletosubsethidden .= "$abb\t$subset\n";
    }
    $subsetssupercolumns++;
    $columns->{ $subset } = scalar( keys %$columns );
    if ( $metass->{ 'view' }->{ 'Subsets' }->{ $subset }->{ 'visible' } ) {
      if ( $metass->{ 'view' }->{ 'Subsets' }->{ $subset }->{ 'collapsed' } ) {
	$visible->{ $subset } = 1;
      }
      else {
	my $ssvals = $subsets->{ $subset };
      }
    }
  }

  foreach my $role ( @$roles ) {
    my $rolesubsystem = $role->[0].'##-##'.$role->[3];
    if ( defined( $th->{ $rolesubsystem } && $th->{ $rolesubsystem }->{ 'visible' } ) ) {
      $visible->{ $rolesubsystem } = 1;
    }
    if ( defined( $role_to_group->{ $rolesubsystem } ) ) {
      $visible->{ $rolesubsystem } = 1;

      my @sss = @{ $role_to_group->{ $rolesubsystem } };
      foreach my $ss ( @sss ) {
	if ( $metass->{ 'view' }->{ 'Subsets' }->{ $ss }->{ 'visible' } ) {
	  if ( $metass->{ 'view' }->{ 'Subsets' }->{ $ss }->{ 'collapsed' } ) {
	    $visible->{ $rolesubsystem } = 0;
	  }
	}
      }      
    }

    $role_to_function->{ $rolesubsystem } = $role->[1];
    $function_to_role->{ $role->[1] } = $role->[2];

    $columns->{ $rolesubsystem } = scalar( keys %$columns );
  }

  ##########################################
  # COLORING SETTINGS OF GENES AND GENOMES #
  ##########################################
  my $peg_to_color_alround;
  my $cluster_colors_alround = {};
  my $genome_colors;
  my $genomes_to_color = {};
  my $columnNameHash;
  my $ind_to_subset;
  my $name = $self->{ 'cgi' }->param( 'metasubsystem' );

  ### COLOR GENES ###
  my $color_by = 'do not color'; #default
  if ( $preferences->{ $name."_color_stuff" } ) {
    $color_by = $preferences->{ $name."_color_stuff" }->value;
  }
  if ( defined( $self->{ 'cgi' }->param( 'color_stuff' ) ) ) {
    $color_by = $self->{ 'cgi' }->param( 'color_stuff' );
    unless ( $preferences->{ $name."_color_stuff" } ) {
      if ( defined( $user ) && ref( $user ) ) {
	$preferences->{ $name."_color_stuff" } = $self->application->dbmaster->Preferences->create( { user        => $user,
												      application => $self->application->backend,
												      name        => $name."_color_stuff",
												      value       => $color_by } );
      }
    }
    else {
      $preferences->{ $name."_color_stuff" }->value( $color_by );
    }
  }
  elsif ( $preferences->{ $name."_color_stuff" } ) {
    $self->{ 'cgi' }->param( 'color_stuff', $preferences->{ $name."_color_stuff" }->value );
  }

  if ( $color_by eq 'by attribute: ' ) {
    my $attr = 'Essential_Gene_Sets_Bacterial';
    
    if ( $preferences->{ $name."_color_by_peg_tag" } ) {
      $attr = $preferences->{ $name."_color_by_peg_tag" }->value;
    }
    if ( defined( $self->{ 'cgi' }->param( 'color_by_peg_tag' ) ) ) {
      $attr = $self->{ 'cgi' }->param( 'color_by_peg_tag' );
      unless ( $preferences->{ $name."_color_by_peg_tag" } ) {
	if ( $user ) {
	  $preferences->{ $name."_color_by_peg_tag" } = $self->application->dbmaster->Preferences->create( { user        => $user,
													     application => $self->application->backend,
													     name        => $name."_color_by_peg_tag",
													     value       => $attr } );
	}
      }
      else {
	$preferences->{ $name."_color_by_peg_tag" }->value( $attr );
      }
    }

    ( $peg_to_color_alround, $cluster_colors_alround ) = $self->get_color_by_attribute_infos( $attr, $pegsarr, $colors );
  }

  ### COLOR GENOMES ###
  my $colorg_by = 'do not color';
  if ( $preferences->{ $name."_colorg_stuff" } ) {
    $colorg_by = $preferences->{ $name."_colorg_stuff" }->value;
  }
  if ( defined( $self->{ 'cgi' }->param( 'colorg_stuff' ) ) ) {
    $colorg_by = $self->{ 'cgi' }->param( 'colorg_stuff' );
    unless ( $preferences->{ $name."_colorg_stuff" } ) {
      if ( $user ) {
	$preferences->{ $name."_colorg_stuff" } = $self->application->dbmaster->Preferences->create( { user        => $user,
												       application => $self->application->backend,
												       name        => $name."_colorg_stuff",
												       value       => $color_by } );
      }
    }
    else {
      $preferences->{ $name."_colorg_stuff" }->value( $colorg_by );
    }
  }
  elsif ( $preferences->{ $name."_colorg_stuff" } ) {
    $self->{ 'cgi' }->param( 'colorg_stuff', $preferences->{ $name."_colorg_stuff" }->value );
  }

  if ( $colorg_by eq 'by attribute: ' ) {
    
    my $attr;
    if ( $preferences->{ $name."_color_by_ga" } ) {
      $attr = $preferences->{ $name."_color_by_ga" }->value;
    }

    if ( defined( $self->{ 'cgi' }->param( 'color_by_ga' ) ) && $self->{ 'cgi' }->param( 'color_by_ga' ) ne '' ) {
      $attr = $self->{ 'cgi' }->param( 'color_by_ga' );

      unless ( $preferences->{ $name."_color_by_ga" } ) {
	if ( $user ) {
	  $preferences->{ $name."_color_by_ga" } = $self->application->dbmaster->Preferences->create( { user        => $user,
														  application => $self->application->backend,
														  name        => $name."_color_by_ga",
														  value       => $attr } );
	}
      }
      elsif ( defined( $attr ) ) {
	$preferences->{ $name."_color_by_ga" }->value( $attr );
	$self->{ 'cgi' }->param( 'color_by_ga', $attr );
      }
      ( $genomes_to_color, $genome_colors ) = $self->get_color_by_attribute_infos_for_genomes( $spreadsheet_hash, $colors );
    }
  }

  ## END OF COLORING SETTINGS ##

  ################################
  # Creating the table from here #
  ################################

  my $javascriptstring = '';

  # create table headers
  my $table_columns = [ '', 
			{ name => 'Organism', filter => 1, sortable => 1, width => '150', operand => $self->{ 'cgi' }->param( 'filterOrganism' ) || '' }, 
			{ name => 'Domain', filter => 1, operator => 'combobox', operand => $self->{ 'cgi' }->param( 'filterDomain' ) || '' }, 
			{ name => 'Taxonomy', sortable => 1, visible => 0, show_control => 1 }, 
			{ name => 'Variant', sortable => 1 }
		      ];
    
  my $supercolumns = [ [ '', 1 ], [ '', 1 ], [ '', 1 ], [ '', 1 ], [ '', 1 ] ];

  # if user can write he gets a writable variant column that if first invisible
  if ( $self->{ 'can_alter' } ) {
    push @$table_columns, { name => 'Variant', visible => 0 };
    push @$supercolumns, [ '', 1 ];
  }
 
  if ( $subsetssupercolumns > 0 ) {
    push @$supercolumns, [ 'Subsets', $subsetssupercolumns ];
  }
  my $supercolstobe;

  my $ii = 4; # this is for keeping in mind in what column we start the Functional Roles
  if ( $self->{ 'can_alter' } ) {
    $ii++;
  }

  my $i = $ii;

  ### Now add the column headers for all functional roles or subsets of the table ###
  foreach my $column ( sort { $columns->{ $a } <=> $columns->{ $b } } keys( %$columns) ) {
    $i++;

    if ( exists( $role_to_function->{ $column } ) ) {
      $column =~ /(.*)\#\#\-\#\#(.*)/;
      my $colrole = $1;
      my $ss_of_role = $2;
      my $tooltip = "<TABLE><TR><TH>Role</TH><TH>Subsystem</TH></TR>\n";
      $tooltip .= "<TR><TD>".$role_to_function->{ $column }."</TD><TD>$ss_of_role</TD></TR></TABLE>";
#      if ( $visible->{ $column } ) {
	push @$supercolstobe, [ $ss_of_role, 1 ];
#      }
      push( @$table_columns, { name => $colrole, tooltip => $tooltip, visible => $visible->{ $column } || 0 } );
      $columnNameHash->{ $i } = $colrole.'<BR>'.$tooltip;
      $javascriptstring .= "\n$column\t$i";
      $ind_to_subset->{ $i } = 1;
    }
    else {
      my $tooltip = "<table>";
      $tooltip .= "<tr><th colspan=2>Subset $column</th></tr>";
      foreach my $role ( keys %{ $subsets->{ $column } } ) {
	$role =~ /(.*)##-##(.*)/;
	$tooltip .= "<tr><td>$1</td><td><b>$2</b></td></tr>";
      }
      $tooltip .= "</table>";
      push( @$table_columns, { name => $column, tooltip =>  $tooltip, visible => $visible->{ $column } || 0 } );
      $columnNameHash->{ $i } = $column.'<BR>'.$tooltip;
      $javascriptstring .= "\n$column\t$i";
    }
  }
  push( @$table_columns, { name => 'Pattern', sortable => 1, visible => 0, show_control => 1 });
  

  # Variants - default is not to show the -1 variants, so we have to ask if that is still true.
  my $show_mo_variants = 0;
  if ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'MoVariants' || $self->{ 'cgi' }->param( 'showMoVariants' ) ) {
    $show_mo_variants = 1;
  }
  if ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'HideOneMOVariants' ) {
    $show_mo_variants = -1;
  }
  if ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'HideAllMOVariants' ) {
    $show_mo_variants = 0;
  }

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

    if ( defined( $self->{ 'activeSubsetHash' } ) ) {
      next unless ( $self->{ 'activeSubsetHash' }->{ $g } );
    }

    my $new_row;
    
    # organism name, domain, taxonomy, variantcode #
    my $gname = $spreadsheet_hash->{ $g }->{ 'name' };
    my $domain = $spreadsheet_hash->{ $g }->{ 'domain' };
    my $tax = $spreadsheet_hash->{ $g }->{ 'taxonomy' };
    my $variant = $spreadsheet_hash->{ $g }->{ 'variant' };

    if ( $show_mo_variants ne '1' ) {    
      # need a new way to handle variants here.
      my @var_subs = split( "\_", $variant );
      my $countvars = 0;
      foreach my $vs ( @var_subs ) {
	if ( $vs eq '-1' ) {
	  $countvars++;
	}
      }
      if ( $show_mo_variants == -1 && $countvars > 0 ) {
	next;
      }
      if ( $show_mo_variants == 0 && $countvars == scalar( @var_subs ) ) {
	next;
      }
    } 
    


    # add link to Organism page here #
    $gname = "<A HREF='seedviewer.cgi?page=Organism&organism=" . $g."' target=_blank>$gname</A>";

    my $gentry = $gname;
    if ( defined( $genomes_to_color->{ $g } ) ) {
      $gentry = "<span style='background-color: " . $genome_colors->{ $genomes_to_color->{ $g } } . ";'>$gname</span>";
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
    push( @$new_row, $variant );
    if ( $self->{ 'can_alter' } ) {
      push( @$new_row, "<INPUT TYPE=TEXT NAME=\"variant$g\" SIZE=5 VALUE=\"$variant\">" );
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

      my $roleident = $roles->[$i]->[0].'##-##'.$roles->[$i]->[3];

      if ( exists( $role_to_group->{ $roleident } ) ) {
	my $subsetsofthisrole = $role_to_group->{ $roleident };

	my $thiscell = '';
	foreach my $ss ( @$subsetsofthisrole ) {
	  my $index = $columns->{ $ss };
	  unless ( $row[$i] =~ /INPUT/ ) {
	    push( @{ $data_cells->[ $index ] }, split( /, /, $row[$i] ) );
	  }
	}	  
      } 
#      else {
	my $index = $columns->{ $roleident };
	push( @{ $data_cells->[ $index ] }, split( /, /, $row[$i] ) );
      }
#    }

    foreach my $p ( @$pegs ) {
      if ( $p =~ /(fig\|\d+\.\d+\.peg\.\d+)/ ) {
	push @$rawpegs, $p;
      } 
    }

    my $peg_to_color;
    my $cluster_colors;

    # if we wanna color by cluster put it in here 
    if ( $color_by eq 'by cluster' ) {

      # compute clusters
      my @clusters = $self->{ 'fig' }->compute_clusters( $rawpegs, undef, 5000 );

      for ( my $i = 0; $i < scalar( @clusters ); $i++ ) {

	my %countfunctions = map{ (scalar $self->{ 'fig' }->function_of( $_ ) => 1 ) } @{ $clusters[ $i ] };
	next unless ( scalar( keys %countfunctions ) > 1);

	foreach my $peg ( @{ $clusters[ $i ] } ) {
	  $peg_to_color->{ $peg } = $i;
	}
      }
    }
    elsif ( $color_by eq 'by attribute: ' ) {
      $peg_to_color = $peg_to_color_alround;
      $cluster_colors = $cluster_colors_alround;
    }


    # print actual cells
    my $pattern = "a";
    my $ind = $ii;
    foreach my $data_cell ( @$data_cells ) {
      $ind++;
      my $num_clustered = 0;
      my $num_unclustered = 0;
      my $cluster_num = 0;
      if ( defined( $data_cell ) ) {
	$data_cell = [ sort( @$data_cell ) ];
	my $cell = {};

	#
	# If we have a zero variant, force the subset column for that
	# subsystem to -.
	#

	if ($self->{plusminus})
	{
	    my $si = $ind - $ii - 1;
	    my $there;
	    my @var_subs = split( "\_", $variant );
	    
	    if ($si < @var_subs && $var_subs[$si] eq '0')
	    {
		$there = '-';
	    }
	    else
	    {
		$there = ((@$data_cell) > 0) ? '+' : '-';
	    }
	    my $tt = $columnNameHash->{ $ind };
	    push( @$new_row, { data => $there, tooltip => $tt } );
	}
	else {
	  foreach my $peg ( @$data_cell ) {
	  
	    if ( $peg =~ /(fig\|\d+\.\d+\.peg\.\d+)/ ) {
	      my $thispeg = $1;
	      my $pegf = $self->{ 'fig' }->function_of( $thispeg );
	      my $pegfnum = '';
	      
	      if ( !defined( $thispeg ) ) {
		next; 
	      }
	      
	      $thispeg =~ /fig\|\d+\.\d+\.peg\.(\d+)/;
	      my $n = $1;
	      
	      my $peg_link = $self->fid_link( $thispeg );
	      $peg_link = "<A HREF='$peg_link' target=_blank>$n</A>";
	      unless ( $ind_to_subset->{ $ind } ) {
		my $add_to_peg = $self->get_peg_addition( $pegf );
		$peg_link .= $add_to_peg;
	      }
	      
	      if ( exists( $peg_to_color->{ $peg } ) ) {
		unless ( defined( $cluster_colors->{ $peg_to_color->{ $peg } } ) ) {
		  $cluster_colors->{ $peg_to_color->{ $peg } } = $colors->[ scalar( keys( %$cluster_colors ) ) ];
		}
		$cluster_num = scalar( keys( %$cluster_colors ) );
		$num_clustered++;
		$cell->{ "<span style='background-color: " . $cluster_colors->{ $peg_to_color->{ $peg } } . ";'>$peg_link</span>" } = 1;
	      }
	      else {
		$num_unclustered++;
		$cell->{ "<span>$peg_link</span>" } = 1;
	      }
	    }
	    else {
	      $cell->{ $peg } = 1;
	    }
	  }
	  my $tt = $columnNameHash->{ $ind };
	  push( @$new_row, { data => join( '<br>', keys %$cell ), tooltip => $tt } );
	}
      }
      else {
	my $tt = $columnNameHash->{ $ind };
	push( @$new_row, { data => '', tooltip => $tt } );
      }
      $pattern .= $num_clustered.$num_unclustered.$cluster_num;
    }
    # pattern
    push(@$new_row, $pattern);

    # push row to table
    push(@$pretty_spreadsheet, $new_row);
  }

  ### create table from parsed data ###
  
  my $table = $application->component( 'SubsystemSpreadsheet' );
  $table->columns( $table_columns );
  $table->data( $pretty_spreadsheet );
  $table->show_top_browse( 1 );
  $table->show_export_button( { strip_html => 1,
				hide_invisible_columns => 1,
			        title      => 'Export plain data to Excel' } );

  my $ss;
  my $ssval = 0;
  foreach my $thisarr ( @$supercolstobe ) {
    if ( !defined( $ss ) ) {
      $ss = $thisarr->[0];
      $ssval++;
    }
    elsif ( $ss eq $thisarr->[0] ) {
      $ssval++;
    }
    else {
      my $nicess = $ss;
      $nicess =~ s/\_/ /g;
      push @$supercolumns, [ $nicess, $ssval ];
      $ss = $thisarr->[0];
      $ssval = 1;
    } 
  }
  if ( defined( $ss ) ) {
      my $nicess = $ss;
      $nicess =~ s/\_/ /g;
      push @$supercolumns, [ $nicess, $ssval ];
  }

  $table->supercolumns( $supercolumns );

  $table->show_select_items_per_page( 1 );

  ### remember some hidden values ###

  my $hiddenvalues = { 'filterOrganism' => '',
		       'sortOrganism'   => '',
		       'filterDomain'   => '',
		       'tableid'        => $table->id,
		       'showMoVariants' => $show_mo_variants,
		       'javascripthidden' => $javascriptstring,
		       'roletosubsethidden' => $roletosubsethidden };

  # finished
  return ( $hiddenvalues );
}


######################################
# Panel for coloring the spreadsheet #
######################################
sub color_spreadsheet_panel {

  my ( $self, $preferences, $name ) = @_;

  my $content = "<H2>Color genes in spreadsheet</H2>";

  my $default_coloring = $self->{ 'cgi' }->param( 'color_stuff' ) || 'do not color';

  if ( !defined( $self->{ 'cgi' }->param( 'color_by_peg_tag' ) ) && defined( $preferences->{ $name."_color_by_peg_tag" } ) ) {
    $self->{ 'cgi' }->param( 'color_by_peg_tag', $preferences->{ $name."_color_by_peg_tag" }->value );
  }

  my $defaultg_coloring = 'do not color';
  if ( defined( $self->{ 'cgi' }->param( 'colorg_stuff' ) ) ) {
    $defaultg_coloring = $self->{ 'cgi' }->param( 'colorg_stuff' );
  }

  my @color_opt = $self->{ 'cgi' }->radio_group( -name     => 'color_stuff',
				     -values   => [ 'do not color', 'by cluster', 'by attribute: ' ],
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
    $content .= "<BR><BR><INPUT TYPE=BUTTON VALUE='Color Spreadsheet' ONCLICK='SubmitSpreadsheet( \"Color Spreadsheet\", 1 );'>";
  }
  else {
    $content .= "<BR><BR><INPUT TYPE=BUTTON VALUE='Color Spreadsheet' ONCLICK='SubmitSpreadsheet( \"Color Spreadsheet\", 0 );'>";
  }

  return $content;
}

###############
# data method #
###############
sub get_metass_data {

  my ( $self ) = @_;

  my $meta = $self->{ 'metasubsystem' };

  my $subsystems = $meta->{ 'subsystems' };

  my ( $subsets, $spreadsheet, $allpegs );
  my $counter = 0;
  my @roles;  
  my %spreadsheethash;
  my @supercolumns;

  my $frtable = $self->application->component( 'FunctionalRolesTable' );
  $frtable->columns( [ '#', 'Subsystem', 'Abbr.', 'Role Name' ] );
  my $frtablerows;

  my @genomes = keys %{ $meta->{ 'genomes' } };
  my $role_counter = 0;

  foreach my $ssname ( keys %$subsystems ) {
    my $subsystem = $subsystems->{ $ssname };
    my $esc_ssname = uri_escape( $ssname );
    my $sslink = qq~<A HREF=\"SubsysEditor.cgi?page=ShowSpreadsheet&subsystem=$ssname\" target=_blank>$ssname</A>~;

    $counter ++;
    
    ## get da roles ##
    my @rs = $subsystem->get_roles();
    foreach my $r ( @rs ) { 
      $role_counter++;
      my $abb = $subsystem->get_abbr_for_role( $r );
      my $in = $subsystem->get_role_index( $r );
      push @{ $self->{ 'roles_to_num' }->{ $r } }, [ $role_counter, $abb.'##-##'.$ssname ];
#      $self->{ 'abb_ss_to_num' }->{ $abb.'##-##'.$ssname } = $role_counter;


      push @roles, [ $abb, $r, $in, $ssname ];
      push @$frtablerows, [ $role_counter, $sslink, $abb, $r ];
    }
    
    foreach my $genome ( @genomes ) {
      my $gidx = $subsystem->get_genome_index( $genome );
      
      $spreadsheethash{ $genome }->{ 'name' } = $self->{ 'fig' }->genus_species( $genome );
      $spreadsheethash{ $genome }->{ 'domain' } = $self->{ 'fig' }->genome_domain( $genome );
      $spreadsheethash{ $genome }->{ 'taxonomy' } = $self->{ 'fig' }->taxonomy_of( $genome );

      my $var = $subsystem->get_variant_code( $gidx );
      if ( !defined( $gidx ) ) {
	$var = '-';
      }
      if ( defined( $spreadsheethash{ $genome }->{ 'variant' } ) ) {
	$spreadsheethash{ $genome }->{ 'variant' } .= "_$var";
      }
      else {
	$spreadsheethash{ $genome }->{ 'variant' } = $var;
      }

      my $rowss = $subsystem->get_row( $gidx );
      my @row;
      
      foreach my $tr ( @$rowss ) {
	if ( !defined( $gidx ) ) {
	  push @row, '';
	}
	else {
	  if ( defined( $tr->[0] ) ) {
	    push @$allpegs, @$tr;
	    push @row, join( ', ', @$tr );
	  }
	  else {
	    push @row, '';
	  }
	}
      }
      
      push @{ $spreadsheethash{ $genome }->{ 'row' } }, @row;
    }

    $frtable->data( $frtablerows );
  
  }

  ## now get da subsets ##
  my @subsetArr = keys %{ $meta->{ 'subsets' } };
  
  foreach my $subsetname ( @subsetArr ) {
    next if ( $subsetname eq 'All' );
    my @abb_subsets = keys %{ $meta->{ 'subsets' } };
    
    $subsets->{ $subsetname } = $meta->{ 'subsets' }->{ $subsetname };
  }
  
  $self->{ 'data_roles' } = \@roles;
  $self->{ 'data_subsets' } = $subsets;
  $self->{ 'data_spreadsheethash' } = \%spreadsheethash;
  $self->{ 'data_allpegs' } = $allpegs;

}

######################################
# Panel for coloring the spreadsheet #
######################################
sub limit_display_panel {
  
  my ( $self ) = @_;
  
  # create a new subsystem object #
  my $subsets = $self->{ 'metasubsystem' }->{ 'subsets' };

#  my @tmp = grep { $_ ne "All" } sort $subsystem->get_subset_namesR;
  my $genomes = $self->{ 'metasubsystem' }->{ 'genomes' };
  
  my %options = ( "higher_plants"   => "Higher Plants",
		  "eukaryotic_ps"   => "Photosynthetic Eukaryotes",
		  "nonoxygenic_ps"  => "Anoxygenic Phototrophs",
		  "hundred_hundred" => "Hundred by a hundred",
		  "functional_coupling_paper" => "Functional Coupling Paper",
		  "cyano_or_plant" => "Cyanos OR Plants",
		  "ecoli_essentiality_paper" => "E. coli Essentiality Paper",
		  "has_essentiality_data"	=> "Genomes with essentiality data",
		  "" =>  "All"
		);

  my @options = ( 'All',
		   'NMPDR',
		   'BRC',
		   'Hundred by a hundred' );

  my @genomeListsUser = GenomeLists::getListsForUser();
  unshift @genomeListsUser, 'All';

  my @allsets = keys %$subsets;
  my @starsets = @allsets;
    
  my $content .= "<P>Limit display of the the genomes in the table based on phylogeny or one of the preselected groups in the left box. Limit display of roles via their subsets and decide which subsets you want to uncollapse in the right box:<P>\n";
  
  # put in table #
  $content .= "<TABLE><TR><TD>";

  # build a little table for the genomes limiting
  $content .= "<H2>&nbsp; Limit displayed Genomes</H2><TABLE><TR><TD>";

  $content .= "<B>Phylogeny</B></TD><TD><B>Specific Sets</B></TD><TD><B>User Sets</B></TD></TR><TR><TD>";

  # phylogeny here #
  my ( $phylo, $row_ss_members ) = $self->get_phylo_groups();
#  $self->{ 'row_subset_members' } = $row_ss_members;
  $content .= $self->{ 'cgi' }->scrolling_list( -id      => 'phylogeny_set',
				    -name    => 'phylogeny_set',
				    -values  => [ "All", sort @$phylo ],
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
  $content .= "</TD></TR></TABLE>\n";
  $content .= "</TD></TR>\n</TABLE>";

  if ( $self->{ 'can_alter' } ) {
    $content .= "<BR><BR><INPUT TYPE=BUTTON VALUE='Limit Display' ONCLICK='SubmitSpreadsheet( \"LimitDisplay\", 1 );'>";
  }
  else {
    $content .= "<BR><BR><INPUT TYPE=BUTTON VALUE='Limit Display' ONCLICK='SubmitSpreadsheet( \"LimitDisplay\", 1 );'>";
  }

  return $content;
}


######################################
# Panel for coloring the spreadsheet #
######################################
sub limit_subsets_panel {
  
  my ( $self ) = @_;
  
  # create a new subsystem object #
  my $subsets = $self->{ 'metasubsystem' }->{ 'subsets' };

  my @allsets = keys %$subsets;
  my @starsets = @allsets;

  my @roles = @{ $self->{ 'data_roles' } };
  my %roles;
  my %abbtofr;
  foreach my $r ( @roles ) { 
    $roles{ $r->[0].'##-##'.$r->[3] } = $r; 
  }

  my $subsets_table = $self->application->component( 'LD_SUBSETS' );
  my $roles_table = $self->application->component( 'LD_ROLES' );

  my $sstdata = [];
  foreach my $set ( @allsets ) {
    my $show_checked = $self->{ 'metasubsystem' }->{ 'view' }->{ 'Subsets' }->{ $set }->{ 'visible' } || 0;
    my $collapse_checked = $self->{ 'metasubsystem' }->{ 'view' }->{ 'Subsets' }->{ $set }->{ 'collapsed' } || 0;

    my $show_set = $self->{ 'cgi' }->checkbox( -name     => 'show_set',
					       -id       => "show_set_$set",
					       -value    => "show_set_$set",
					       -label    => '',
					       -checked  => $show_checked,
					     );
    my $collapse_set = $self->{ 'cgi' }->checkbox( -name     => 'collapse_set',
						   -id       => "collapse_set_$set",
						   -value    => "collapse_set_$set",
						   -label    => '',
						   -checked  => $collapse_checked,
						 );

    my @mems = keys %{ $subsets->{ $set } };
    my @nicemems;
    my @nicesubsystems;
    foreach ( @mems ) {
      $self->{ 'in_subset_role' }->{ $_ } = 1;
      if ( $_ =~ /([^#^-]+)##-##(.*)/ ) {
	push @nicemems, $1;
	push @nicesubsystems, $2;
      }
    }

    my $row = [ $set, { data => join( ', ', @nicemems ), tooltip => join( ', ', @nicesubsystems ) },
		$show_set, $collapse_set ];

    push @$sstdata, $row;
  }

  my $rowdata = [];
  my %rowdatahash;
  foreach my $r ( sort keys %roles ) {
    next if ( defined( $self->{ 'in_subset_role' }->{ $r } ) );
    my $checkid = "show_role_$r";

    my $show_checked = 0;
    if ( $self->{ 'metasubsystem' }->{ 'view' }->{ 'Roles' }->{ $r }->{ 'visible' } ) {
      $show_checked = 1;
    }

    my $show_set = $self->{ 'cgi' }->checkbox( -name     => 'show_role',
					       -id       => "$checkid",
					       -value    => "$checkid",
					       -label    => '',
					       -checked  => $show_checked,
					     );
    $r =~ /(.*)##-##.*/;

    $rowdatahash{ $roles{ $r }->[3] }->{ $1 }->{ 'funcrole' } = $roles{ $r }->[1];
    $rowdatahash{ $roles{ $r }->[3] }->{ $1 }->{ 'checkbox' } = $show_set;
  }

  my $isrow = 0;
  foreach my $subsys ( keys %rowdatahash ) {
    my $count = 0;
    my @row = ( $subsys );
    foreach my $abb ( keys %{ $rowdatahash{ $subsys } } ) {
      $count++;
      $isrow = 1;
      push @row, { data => $abb."<BR>".$rowdatahash{ $subsys }->{ $abb }->{ 'checkbox' }, tooltip => $rowdatahash{ $subsys }->{ $abb }->{ 'funcrole' } };
      if ( $count > 8 ) {
	$count = 0;
	push @$rowdata, [ @row ];
	@row = ( $subsys );
      }
    }
    if ( $count > 0 ) {
      for( my $i = $count; $i <= 8; $i++ ) {
	push @row, '';
      }
      push @$rowdata, [ @row ];
    }
  }

  if ( scalar( @$sstdata ) > 0 ) {
    $subsets_table->columns( [ 'Name', 'Members', 'Show', 'Collapse' ] );
    $subsets_table->data( $sstdata );
  }
  if ( scalar( @$rowdata ) > 0 ) {
    $roles_table->columns( [ 'Subsystem', '', '', '', '', '', '', '', '', '' ] );
    $roles_table->data( $rowdata );
  }

  my $content = '<TABLE><TR>';
  $content .= "<TD><B>Subsets</B></TD></TR><TR>";
  $content .= "<TD>Choose which subsets should be visible, and for these if they should be displayed collapsed or show each role in a separate column.";
  $content .= "</TD></TR><TR><TD>";
  $content .= $subsets_table->output();
  if ( $isrow ) {
    $content .= '</TD></TR><TR>';
    $content .= "<TD><B>Functional Roles</B></TD></TR><TR>";
    $content .= "<TD>The following roles are not part of any defined subsystem. Check the roles you want to see in your display.</TD>";
    $content .= '</TR><TR><TD>';
    $content .= $roles_table->output();
  }
  $content .= '</TD></TR></TABLE>';

  my $spreadsheettable = $self->application->component( 'SubsystemSpreadsheet' );
  my $spreadsheettableid = $spreadsheettable->id();

  $content .= "<BR><BR><INPUT TYPE=BUTTON VALUE='Limit Subsets and Functional Roles' ONCLICK='ChangeVisibility( \"$spreadsheettableid\" );'>";
  if ( $self->{ 'can_alter' } ) {
    $content .= "<INPUT TYPE=BUTTON VALUE='Make current setting Default' ONCLICK='SubmitSpreadsheet( \"LimitSubsets\", 2 );'>";
  }

  return $content;
}


sub fid_link {
    my ( $self, $fid ) = @_;
    my $n;
    my $seeduser = $self->{ 'seeduser' };
    $seeduser = '' if ( !defined( $seeduser ) );

    if ($fid =~ /^fig\|\d+\.\d+\.([a-zA-Z]+)\.(\d+)/) {
      if ( $1 eq "peg" ) {
	  $n = $2;
	}
      else {
	  $n = "$1.$2";
	}
    }

#    return "./protein.cgi?prot=$fid&user=$seeduser\&new_framework=0";
    return qq~./seedviewer.cgi?page=Annotation&feature=$fid&user=$seeduser~;
}



sub get_color_by_attribute_infos {

  my ( $self, $attr, $pegsarr, $colors ) = @_; 

  my $scalacolor = is_scala_attribute( $attr );
  my $peg_to_color_alround;
  my $cluster_colors_alround;
  
  if ( defined( $attr ) ) {
    my $groups_for_pegs = get_groups_for_pegs( $self->{ 'fig' }, $attr, $pegsarr );
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
      $self->{ 'legend' } = get_scala_legend( $biggestitem, $smallestitem, 'Color legend for CDSs' );
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
      $self->{ 'legend' } = get_value_legend( $leghash, 'Color Legend for CDSs' );
    }
  }
  return ( $peg_to_color_alround, $cluster_colors_alround );
}

sub get_peg_addition {

  my ( $self, $pegf ) = @_;

#  my @frs = split( ' / ', $pegf );
  my @frs = ( split( /\s*;\s+|\s+[\@\/]\s+/, $pegf ) );
  my $pegfnum = '';

  foreach ( @frs ) {
    my $m = $self->{ 'roles_to_num' }->{ $_ };
    next if ( !defined( $m ) );

    foreach my $pm ( @$m ) {
      my $pegfnumtmp = $pm->[0];
      $pegfnum .= '_'.$pegfnumtmp;
    }
  }
  return $pegfnum;
}

sub get_color_by_attribute_infos_for_genomes {
  
  my ( $self, $spreadsheethash, $colors ) = @_; 
  
  my $genomes_to_color;
  my $genome_colors;
  my $leghash;
  my $i = 0;
  my $biggestitem = 0;
  my $smallestitem = 100000000000;
  
  my $attr = $self->{ 'cgi' }->param( 'color_by_ga' );
  my $scalacolor = is_scala_attribute( $attr );
  
  my @genomes = keys %$spreadsheethash;
  my $groups_for_genomes = get_groups_for_pegs( $self->{ 'fig' }, $attr, \@genomes );

  if ( $scalacolor ) {
    
    foreach my $item ( keys %$groups_for_genomes ) {
      
      if ( $biggestitem < $item ) {
	$biggestitem = $item;
      }
      if ( $smallestitem > $item ) {
	$smallestitem = $item;
      }
    }
    $self->{ 'legendg' } = get_scala_legend( $biggestitem, $smallestitem, 'Color Legend for Genomes' );
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
    $self->{ 'legendg' } = get_value_legend( $leghash, 'Color Legend for Genomes' );
  }

  return ( $genomes_to_color, $genome_colors );
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


#####################################################
# List of attributes that are not used for coloring #
#####################################################
sub attribute_blacklist {

  my $list = { 'pfam-domain' => 1,
	       'PFAM'        => 1,
	       'CDD'         => 1 };
  return $list;

}

sub get_phylo_groups {
  my ( $self ) = @_;

  my @row_subsets;
  my $row_subset_members;

  my $taxonomic_groups = $self->{ 'fig' }->taxonomic_groups_of_complete(10);
  foreach my $pair ( @$taxonomic_groups ) {
    my ( $id, $members ) = @$pair;
    if ( $id ne "All" ) {
      push( @row_subsets, $id );
    }
    $row_subset_members->{ $id } = $members;
  }
  return ( \@row_subsets, $row_subset_members );
}


sub getActiveSubsetHash {

  my ( $self ) = @_;

  my $activeR;
  my $evaluate = 0;
  my $andor;

  my $phylo = $self->{ 'cgi' }->param( 'phylogeny_set' );
  my $special = $self->{ 'cgi' }->param( 'special_set' );
  my $userset = $self->{ 'cgi' }->param( 'user_set' );

  if ( defined( $special ) && $special ne '' && $special ne 'All' ) {
    my @subsetspecial = moregenomes( $self, $special );
    my %activeRH = map { $_ => 1 } @subsetspecial;
    $activeR = \%activeRH;
    $evaluate = 1;
  }
  if ( defined( $phylo ) && $phylo ne '' && $phylo ne 'All' ) {
    my %genomes = %{ $self->{ 'metasubsystem' }->{ 'genomes' } };
    my @subsetR = grep { $genomes{ $_ } } @{ $self->{ 'row_subset_members' }->{ $phylo } };

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

  return $activeR;
}



sub selectgenomeattr {
  my ( $self, $tag, $value )=@_;
  my @orgs;

  if ( $tag eq "phylogeny" ) {
    my $taxonomic_groups = $self->{ 'fig' }->taxonomic_groups_of_complete(10);
    foreach my $pair (@$taxonomic_groups)
      { 
	push @orgs, @{$pair->[1]} if ($pair->[0] eq "$value");
      }
  }
  elsif ( $tag eq "filepresent" ) {
    foreach my $genome ( $self->{ 'fig' }->genomes ) {
      push(@orgs, $genome) if (-e $FIG_Config::organisms."/$genome/$value");
    }
  }
  else {
    if ( $value ) {
      @orgs = map { $_->[0]} grep {$_->[0] =~ /^\d+\.\d+$/ } $self->{ 'fig' }->get_attributes( undef, $tag, $value );
    }
    else {
      @orgs = map { $_->[0]} grep {$_->[0] =~ /^\d+\.\d+$/ } $self->{ 'fig' }->get_attributes( undef, 'collection', $tag );
    }
  }
  return @orgs;
}

#################################
# Buttons under the spreadsheet #
#################################
sub get_spreadsheet_buttons {
  my ( $self ) = @_;
  
  my $plusminus = "<INPUT TYPE=BUTTON VALUE='PlusMinus View' ID='PLUSMINUS' NAME='PLUSMINUS' ONCLICK='SubmitSpreadsheet( \"PLUSMINUS\", 0 );'>";
  my $notplusminus = "<INPUT TYPE=BUTTON VALUE='Normal View' ID='NOTPLUSMINUS' NAME='NOTPLUSMINUS' ONCLICK='SubmitSpreadsheet( \"NOTPLUSMINUS\", 0 );'>";

  my $delete_button = "<INPUT TYPE=HIDDEN VALUE=0 NAME='DeleteGenomesHidden' ID='DeleteGenomesHidden'>";
  $delete_button .= "<INPUT TYPE=BUTTON VALUE='Delete selected genomes' NAME='DeleteGenomes' ID='DeleteGenomes' ONCLICK='if ( confirm( \"Do you really want to delete the selected genomes from the spreadsheet?\" ) ) { 
 document.getElementById( \"DeleteGenomesHidden\" ).value = 1;
SubmitSpreadsheet( \"DeleteGenomes\", 0 ); }'>";
  my $minus1_variant_button = "<INPUT TYPE=BUTTON VALUE='Show all variants' NAME='MoVariants' ID='MoVariants' ONCLICK='SubmitSpreadsheet( \"MOVariants\", 0 );'>";
  my $minus1_variant_hideall_button = "<INPUT TYPE=BUTTON VALUE='Hide variants all subsystems -1' NAME='HideAllMOVariants' ID='HideAllMOVariants' ONCLICK='SubmitSpreadsheet( \"HideAllMOVariants\", 0 );'>";
  my $minus1_variant_hideone_button = "<INPUT TYPE=BUTTON VALUE='Hide variants one subsystem -1' NAME='HideOneMOVariants' ID='HideOneMOVariants' ONCLICK='SubmitSpreadsheet( \"HideOneMOVariants\", 0 );'>";

  my $spreadsheetbuttons = "<DIV id='controlpanel'><H2>Actions</H2>\n";
  
  $spreadsheetbuttons .= "<TABLE><TR><TD><B>Variants:</B></TD><TD>$minus1_variant_button</TD><TD>$minus1_variant_hideone_button</TD><TD>$minus1_variant_hideall_button</TD></TR></TABLE><BR>";
  $spreadsheetbuttons .= "<TABLE><TR><TD><B>View:</B></TD><TD>$plusminus</TD></TR></TABLE><BR>";
  $spreadsheetbuttons .= "<TABLE><TR><TD><B>Selection:</B></TD><TD>$delete_button</TD></TR></TABLE><BR>";
  
  return $spreadsheetbuttons;
}


##################################
# Add genomes to the spreadsheet #
##################################
sub add_refill_genomes {
  my ( $self, $genomes ) = @_;
  
  my $comment = "";

  $self->{ 'metasubsystem' }->add_genomes( $genomes );
  $self->{ 'metasubsystem' }->write_metasubsystem();

  $comment .= "Added ". scalar( keys( %$genomes ) ). " genomes to the spreadsheet:<BR>";

  foreach my $g ( keys %$genomes ) {
    $comment .= " - $g <BR>";
  }

  return ( '', $comment );
}

#######################################
# Remove genomes from the spreadsheet #
#######################################
sub remove_genomes {
  my( $self, $genomes ) = @_;

  my $comment = '';

  if ( scalar( @$genomes ) == 0 ) {
    return "No genomes selected to delete<BR>\n";
  }

  my %delgenomes;
  foreach my $genm ( @$genomes ) {
    $genm =~ /^genome_checkbox_(\d+\.\d+.*)/;
    my $genome = $1;
    my $rawgenome = $genome;
    $delgenomes{ $genome } = 1;

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
  }
  
  
  $self->{ 'metasubsystem' }->remove_genomes( \%delgenomes );
  $self->{ 'metasubsystem' }->write_metasubsystem();

  return $comment;
}

##################################
# Upper panel for adding genomes #
##################################
sub add_genomes_panel {

  my ( $self, $application ) = @_;

  ####################################
  # collect some data into variables #
  ####################################
  # get a hash of all genomes of that subsystem #
  my %genomes = %{ $self->{ 'metasubsystem' }->{ 'genomes' } };

  #################################
  # Put The New OrganismSelect in #
  #################################
  my $oselect = $application->component( 'OSelect' );
  $oselect->multiple( 1 );
  $oselect->width( 500 );
  $oselect->name( 'new_genome' );
  $oselect->blacklist( \%genomes );

  my @options = ( 'None',
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
  $addgenomespanel .= "<INPUT TYPE=BUTTON VALUE=\"Show selected\ngenome list\" ID='ShowSelectionButton' ONCLICK='OpenGenomeList( \"".$application->url()."\" );'>";
  $addgenomespanel .= "</TD></TR></TABLE></TD></TR></TABLE>\n";

  $addgenomespanel .= "</TD></TR><TR><TD>";

  $addgenomespanel .= "<INPUT TYPE=BUTTON VALUE='Add selected genome(s) to spreadsheet' ONCLICK='SubmitSpreadsheet( \"Add selected genome(s) to spreadsheet\", 0 );'>";

  $addgenomespanel .= "</TD></TR></TABLE><BR>";


  return $addgenomespanel;
}

sub moregenomes {
  my ( $self, $more ) = @_;
  
  if ($more eq "Cyanobacteria")              { return $self->selectgenomeattr( $self->{ 'fig' }, "phylogeny", "Cyanobacteria")}
  if ($more eq "NMPDR")                      { return $self->selectgenomeattr( $self->{ 'fig' }, "filepresent", "NMPDR")}
  if ($more eq "BRC")                        { return $self->selectgenomeattr( $self->{ 'fig' }, "filepresent", "BRC")}
  if ($more eq "higher_plants")              { return $self->selectgenomeattr( $self->{ 'fig' }, "higher_plants")}
  if ($more eq "eukaryotic_ps")              { return $self->selectgenomeattr( $self->{ 'fig' }, "eukaryotic_ps")}
  if ($more eq "nonoxygenic_ps")             { return $self->selectgenomeattr( $self->{ 'fig' }, "nonoxygenic_ps")}
  if ($more eq "Hundred by a hundred")       { return $self->selectgenomeattr( $self->{ 'fig' }, "hundred_hundred")}
  if ($more eq "functional_coupling_paper")  { return $self->selectgenomeattr( $self->{ 'fig' }, "functional_coupling_paper")}
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
