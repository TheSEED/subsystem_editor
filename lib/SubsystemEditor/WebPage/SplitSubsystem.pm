package SubsystemEditor::WebPage::SplitSubsystem;

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

  $self->application->register_component( 'Table', 'FRTable' );
  $self->application->register_component( 'Info', 'CommentInfo' );
  $self->application->register_component( 'Table', 'FRShowTable' );
  $self->application->register_component( 'TabView', 'SelectionTabView' );
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
  $self->{ 'subsystem' } = $ssname;

  # look if someone is logged in and can write the subsystem #
  $self->{ 'can_alter' } = 0;
  my $user = $self->application->session->user;
  if ( $user && $user->has_right( $self->application, 'edit', 'subsystem', $name ) ) {
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

  # get a subsystem object to handle it #
  my $subsystem = new Subsystem( $name, $self->{ 'fig' }, 0 );
  my ( $comment, $error );

  my $show_namings = 0;
  my $split_now = 0;
  my $frchecks = '';
  my $newnames = '';
  my $splitstuff = '';
  my $hiddenvalues;
  $hiddenvalues->{ 'subsystem' } = $name;

  #########
  # TASKS #
  #########
  my $tabdefault = 1;
  if ( $self->{ 'cgi' }->param( 'Selection' ) ) {
    $show_namings = 1;
    $tabdefault = 2;
  }
  elsif ( $self->{ 'cgi' }->param( 'Split' ) ) {
    $split_now = 1;
  }

  ###################
  # Construct parts #
  ###################
  my ( $putcomment, $puterror );

  if ( $split_now ) {
    $frchecks = $self->functional_role_checks( $subsystem, 1 );
    ( $newnames, $putcomment, $puterror ) = $self->get_new_names( $subsystem );
    ( $splitstuff, $putcomment, $puterror ) = $self->do_split( $subsystem );
    $error .= $puterror if ( defined( $puterror ) );
    $comment .= $putcomment if ( defined( $putcomment ) );
    $tabdefault = 3;
    if ( defined( $error ) && $error ne '' ) {
      $tabdefault = 2;
    }
  }
  elsif ( $show_namings ) {
    $frchecks = $self->functional_role_checks( $subsystem, 1 );
    ( $newnames, $putcomment, $puterror ) = $self->get_new_names( $subsystem, 1 );
    if ( defined( $error ) && $error ne '' ) {
      $tabdefault = 1;
    }
  }
  else {
    $frchecks = $self->functional_role_checks( $subsystem );
  }
  my ( $abbrev, $funcrolestable ) = $self->format_roles( $subsystem );


  my $selecttabview = $self->application->component( 'SelectionTabView' );
  $selecttabview->width( 900 );
  $selecttabview->add_tab( '<H2>&nbsp; Functional Roles &nbsp;</H2>', "$funcrolestable" );
  if ( $self->{ 'can_alter' } ) {
    $selecttabview->add_tab( '<H2>&nbsp; Functional roles to new Subsystems &nbsp;</H2>', "<P>To assign roles to new subsystems, type a number behind each functional role. Each functional role has to belong to one subsystem to perform the splitting.</P>".$frchecks );
    $selecttabview->add_tab( '<H2>&nbsp; Names for new Subsystems &nbsp;</H2>', "<P>You have successfully assigned each role to a new subsystem. Now I need names for the cute new little ones...</P>".$newnames );
    $selecttabview->add_tab( '<H2>&nbsp; Process &nbsp;</H2>', "<P>The subsystem was successfully split. The following subsystems were build:</P>".$splitstuff );
    $selecttabview->default( $tabdefault );
  }

  ###########
  # Content #
  ###########

  my $content = "<H1>Split the subsystem $ssname</H1>";
  $content .= "<P>This is a way to split large subsystems into smaller ones. It works by assigning the roles from the parent subsystem to each of the new ones (kids). Each kid is defined by a number, and this number will specify that a role belongs to a new subsystem.</P>";
 
  if ( $self->{ 'can_alter' } ) {
    $content .= $self->start_form( 'splitsubsystem', $hiddenvalues );
    $content .= $selecttabview->output();
    $content .= $self->end_form();
  }
  else {
    $content .= "<P><I>You are not logged in or you do not have the right to edit this subsystem.</I></P>";
  }

  ###############################
  # Display errors and comments #
  ###############################
 
  if ( defined( $error ) && $error ne '' ) {
    $self->application->add_message( 'warning', $error );
  }

  return $content;
}

sub functional_role_checks {
  my ( $self, $subsystem, $old ) = @_;
  
  my $maxcount = 5;
  my $frtable = $self->application->component( 'FRTable' );
  my @data;
  my @row;

  my @roles = $subsystem->get_roles();

  my $counter = 0;
  foreach my $fr ( @roles ) {
    $counter++;
    my $abk = $subsystem->get_abbr_for_role( $fr );
    my $num = '';

    if ( $old ) {
      $num = $self->{ 'cgi' }->param( 'frtext'.$abk );
    }

    my $fr_text = "<INPUT TYPE=TEXT SIZE=2 NAME='frtext$abk' ID='frtext$abk' VALUE='$num'>";

    push @row, $fr_text;
    push @row, { data => $abk, tooltip => $fr };
    
    if ( $counter > $maxcount ) {
      $counter = 0;
      push @data, [ @row ];
      @row = ();
    }
  }
  
  if ( $counter > 0 ) {
    
    for ( my $i = $counter; $i <= $maxcount; $i++ ) {
      push @row, '';
      push @row, '';
    }
    push @data, [ @row ];
  }

  my $cols;
  for ( my $i = 0; $i <= $maxcount; $i++ ) {
    push @$cols, '';
    push @$cols, '';
  }

  $frtable->columns( $cols );
  $frtable->data( \@data );

  my $html = $frtable->output();
  $html .= "<BR><INPUT TYPE=SUBMIT ID='Selection' Name='Selection' VALUE='Selection'>";

  return $html;
}

sub get_new_names {
  my ( $self, $subsystem, $old ) = @_;
  
  my $newnames = '';
  my %numtorole;

 foreach my $r ( $subsystem->get_roles() ) {
   my $abb = $subsystem->get_abbr_for_role( $r );
   my $num = $self->{ 'cgi' }->param( 'frtext'.$abb );
   if ( defined( $num ) ) {
     push @{ $numtorole{ $num }->{ 'members' } }, $abb;
   }
 }
  
  foreach my $k ( sort keys %numtorole ) {

    my $newname = '';
    $newname = $self->{ 'cgi' }->param( "newname$k" );
    if ( !defined( $newname ) ) {
      $newname = '';
    }

    $newnames .= "Name for $k: <INPUT TYPE=TEXT SIZE=70 NAME='newname$k' ID='newname$k' VALUE='$newname'>";

    my $frviewtable = "<TABLE class='table_table'>";
    foreach my $mem ( @{ $numtorole{ $k }->{ 'members' } } ) {
      $frviewtable .= "<TR><TD class='table_odd_row'>$mem</TD><TD class='table_odd_row'>".$subsystem->get_role_from_abbr( $mem )."</TD></TR>\n";
    }
    $frviewtable .= "</TABLE>";
    $newnames .= $frviewtable."<HR color='#000000' size='2'><BR>";
  }

  my $meta_checkbox = $self->{ 'cgi' }->checkbox( -name     => 'meta_checkbox',
						  -id       => "meta_checkbox",
						  -value    => "meta_checkbox",
						  -label    => 'Check here if you want to build a metasubsystem from your old one',
						  -checked  => 1,
						  -override => 1,
						);

  $newnames .= "<H3>You have the option to preserve the look of your old subsystem by building a metasubsystem</H3>";
  $newnames .= $meta_checkbox."<BR>";

  $newnames .= "<BR><INPUT TYPE=SUBMIT ID='Selection' Name='Split' VALUE='Perform Split'>";

  return ( $newnames, '', '' );
}

sub do_split {
  my ( $self, $subsystem ) = @_;

  my $html = '';
  my %numtorole;
  my $sscreatehash;

  foreach my $r ( $subsystem->get_roles() ) {
    my $abb = $subsystem->get_abbr_for_role( $r );
    my $num = $self->{ 'cgi' }->param( 'frtext'.$abb );
    if ( defined( $num ) ) {
      push @{ $numtorole{ $num }->{ 'members' } }, $abb;
    }
    else {
      return ( $html, '', "Role $abb has no specified subsystem<BR>\n" )
    }
  }
  my %hashnames;

  foreach my $k ( sort keys %numtorole ) {
    my $newname = $self->{ 'cgi' }->param( "newname$k" );

    if ( !defined( $newname ) ) {
      return ( '', '', "Number $k has no name<BR>\n" );
    }
    if ( defined( $hashnames{ $newname } ) ) {
      return ( '', '', "$newname is used more than once, e.g. for $k and ". $hashnames{ $newname }."<BR>" );
    }
    $hashnames{ $newname } = $k;

    $html .= "$k: Subsystem <A HREF='SubsysEditor.cgi?page=ShowSubsystem&subsystem=$newname' target=_blank>$newname<A>";
    $html .= "<BR><BR>";

    foreach my $mem ( @{ $numtorole{ $k }->{ 'members' } } ) {
      my $role = $subsystem->get_role_from_abbr( $mem );
      push @{ $sscreatehash->{ $newname } }, [ $role, $mem ];
    }

  }
  my ( $succ, $err ) = $self->split_subsystem( $subsystem, $sscreatehash );
  if ( defined( $err ) ) {
    return ( '', '', $err );
  }

  my @diagram_list = $subsystem->get_diagrams();
  if ( scalar( @diagram_list ) > 0 ) {
    $html .= "<P><B>The old subsystem has diagrams that can not be preserved:</B><BR>\n";

    foreach my $dia ( @diagram_list ) {
      $html .= "* ".$dia->[0].": ".$dia->[1]."<BR>";
    }
    $html .= "</P>";

  }

  my $filtername = $self->{ 'subsystem' };
  $filtername =~ s/ /_/g;
  my @literature = $self->{ 'fig' }->get_attributes( 'Subsystem:'.$filtername, "SUBSYSTEM_PUBMED_RELEVANT" );

  if ( scalar( @literature ) > 0 ) {
    $html .= "<P><B>The old subsystem has literature that can not be preserved:</B><BR>\n";
    foreach my $lit ( @literature ) {
      my ( $ss, $key, $value ) = @$lit;
      $html .= "* ".$value."<BR>";
    }
  }

  my $error;
  if ( $self->{ 'cgi' }->param( 'meta_checkbox' ) ) {
    my $link = create_meta_subsystem( $self, $self->{ 'subsystem' }, $sscreatehash, $subsystem );
    if ( defined( $link ) ) {
      $html .= $link."<BR>";
    }
    else {
      $error = "Your metasubsystem could not be created. A metasubsystem with this name might already exist.<BR>";
    }
  }

  # delete subsystem (move it to backup)
  $self->remove_subsystem( $subsystem );

  return ( $html, 'Split successful', $error );
}


###############################
# get a functional role table #
###############################
sub format_roles {
    my( $self, $subsystem ) = @_;
    my $i;

    my $col_hdrs = [ "Column", "Abbrev", "Functional Role" ];

    my ( $tab, $abbrevP ) = format_existing_roles( $subsystem );

    # create table from parsed data
    my $table = $self->application->component( 'FRShowTable' );
    $table->columns( $col_hdrs );
    $table->data( $tab );

    my $formatted = $self->application->component( 'FRShowTable' )->output();

    $formatted .= "<BR><BR>";
    return ( $abbrevP, $formatted );
}

#########################################
# get rows of the functional role table #
#########################################
sub format_existing_roles {
    my ( $subsystem ) = @_;
    my $tab = [];
    my $abbrevP = {};

    foreach my $role ( $subsystem->get_roles ) {
      my $i = $subsystem->get_role_index( $role );
      my $abbrev = $role ? $subsystem->get_role_abbr( $i ) : "";
      $abbrevP->{ $role } = $abbrev;
      push( @$tab, [ $i + 1, $abbrev, $role ] );
    }

    return ( $tab, $abbrevP );
}

################################
# actually split the subsystem #
################################
sub split_subsystem {
  my ( $self, $subsystem, $roleshash ) = @_;
  my $error;

  # check if new names are valid
  foreach my $ssname ( keys %$roleshash ) {
    my $newsubsystem = new Subsystem( $ssname, $self->{ 'fig' }, 0 );
    if ( defined( $newsubsystem ) ) { 
      $error .= "Subsystem name $ssname is already in use<BR>";
    }
  }
  if ( defined( $error ) ) {
    return ( 1, $error );
  }

  # first of all, we create the new ones #
  
  my $notes = $subsystem->get_notes();
  my $description = $subsystem->get_description();
  my $classification = $subsystem->get_classification();
  my %hope_reactions = $subsystem->get_hope_reactions();
  my %hope_reaction_notes = $subsystem->get_hope_reaction_notes();
  my %hope_reaction_links = $subsystem->get_hope_reaction_links();
  my $kegg_reactions = $subsystem->get_reactions();
  my $emptycells = $subsystem->get_emptycells();

  foreach my $ssname ( keys %$roleshash ) {
    my $newsubsystem = new Subsystem( $ssname, $self->{ 'fig' }, 1 );
    $newsubsystem->set_roles( $roleshash->{ $ssname } );

    my @thisarr = map { $_->[0] } @{ $roleshash->{ $ssname } };
    my @thisabb = map { $_->[1] } @{ $roleshash->{ $ssname } };

    $newsubsystem->add_to_subsystem( $self->{ 'subsystem' }, \@thisarr );
    if ( defined( $notes ) && $notes ne '' ) {
      $newsubsystem->set_notes( "\nNotes copied from ".$self->{ 'subsystem' }.":\n".$notes );
    }
    if ( defined( $description ) && $description ne '' ) {
      $newsubsystem->set_description( "\nDescription copied from ".$self->{ 'subsystem' }.":\n".$description );
    }
    $newsubsystem->set_classification( $classification );

    # hope reactions #
    foreach my $r ( @thisarr ) {
      if ( defined( $hope_reactions{ $r } ) ) {
	$newsubsystem->set_hope_reaction( $r, join( ',', @{ $hope_reactions{ $r } } ) );
      }
      if ( defined( $kegg_reactions->{ $r } ) ) {
	$newsubsystem->set_reaction( $r, join( ',', @{ $kegg_reactions->{ $r } } ) );
      }
      if ( defined( $hope_reaction_notes{ $r } ) ) {
	$newsubsystem->set_hope_reaction_note( $r, $hope_reaction_notes{ $r } );
      }
      if ( defined( $hope_reaction_links{ $r } ) ) {
	$newsubsystem->set_hope_reaction_link( $r, $hope_reaction_links{ $r } );
      }
    }

    my $newemptycells;
    foreach my $r ( @thisabb ) {
      foreach my $g ( keys %{ $emptycells->{ $r } } ) {
	$newemptycells->{ $r }->{ $g } = $emptycells->{ $r }->{ $g };
      }
    }
    $newsubsystem->set_emptycells( $newemptycells );

    # write spreadsheet #
    $newsubsystem->db_sync();
    $newsubsystem->write_subsystem();
  }
  return ( 1 );
}

sub create_meta_subsystem {
  my ( $self, $msname, $sscreatehash, $old_subsystem ) = @_;
  my $link;
  my @genomes = $old_subsystem->get_genomes();
  my @subsystems = keys %$sscreatehash;
  my $description = $old_subsystem->get_description();
  my $rolehash;
  my $mssubsets;

  foreach my $newname ( @subsystems ) {
    foreach my $ar ( @{ $sscreatehash->{ $newname } } ) {
      $rolehash->{ $ar->[1] } = $newname;
    }
  }

  my %hashgenomes = map { $_ => 1 } @genomes;
  my %hashsubsystems = map { $_ => 1 } @subsystems;


  my @subsets = $old_subsystem->get_subset_namesC();
  foreach my $sub ( @subsets ) {
    next if ( $sub eq "All" );

    my @members= $old_subsystem->get_subsetC( $sub );
    foreach my $idx ( @members ) {
      my $abb = $old_subsystem->get_abbr_for_role( $old_subsystem->get_role( $idx ) );
      $mssubsets->{ $sub }->{ $abb."##-##".$rolehash->{ $abb } } = 1;
    }
    
  }

  my $view;
  
  foreach my $subset ( keys %$mssubsets ) {
    $view->{ 'Subsets' }->{ $subset } = { 'visible' => 1,
					  'collapsed' => 1 };
  }
  
  my $metasstest = new MetaSubsystem( $msname, $self->{ 'fig' }, 0 );
  if ( defined( $metasstest ) ) {
    return undef;
  }

  my $metass = new MetaSubsystem( $msname, $self->{ 'fig' }, 1, \%hashsubsystems, \%hashgenomes, $mssubsets, $view, $description );

  if ( ref( $metass ) ) {
    my $metasubsysurl = "SubsysEditor.cgi?page=MetaInfo&metasubsystem=$msname";
    $link .= "<H3> Creating Metasubsystem $msname was successfull.<BR>";
    $link .= "<H3> Click <A HREF='$metasubsysurl' target = _blank>here</A> to view your new Meta Subsystem</H3>";
  }
  else {
    $link .= "Could not create new Meta Subsystem $msname.</H3>";
  }
  return $link;
}


#######################################
# Remove genomes from the spreadsheet #
#######################################
sub remove_subsystem {
  my( $self, $subsystem ) = @_;

  $subsystem->delete_indices();
  my $name = $self->{ 'subsystem' };
  $name =~ s/ /\_/g;
  
  $self->{ 'fig' }->verify_dir( "$FIG_Config::data/SubsystemsBACKUP" );
  my $cmd = "mv '$FIG_Config::data/Subsystems/$name' '$FIG_Config::data/SubsystemsBACKUP/$name"."_".time."'";
  my $rc = system $cmd;

  return '';
}
