package SubsystemEditor::WebPage::ShowVariants;

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

  $self->application->register_component( 'Table', 'ShowVariantsTable'  );
  $self->application->register_component( 'Table', 'FRTable'  );
  $self->application->register_component( 'Table', 'VarDescTable'  );
  $self->application->register_component( 'Info', 'CommentInfo');
}

sub require_javascript {

  return [ './Html/showfunctionalroles.js' ];

}

##############################################
# Website content is returned by this method #
##############################################
sub output {
  my ( $self ) = @_;

  my $can_alter = 0;
  my $user = $self->application->session->user;
  
  $self->{ 'fig' } = $self->application->data_handle( 'FIG' );
  $self->{ 'cgi' } = $self->application->cgi;
  
  my $name = $self->{ 'cgi' }->param( 'subsystem' );
  my $ssname = $name;
  $name = uri_unescape( $name );
  $ssname =~ s/\_/ /g;

  my $esc_name = uri_escape($name);

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
    $can_alter = 1;
    $self->{ 'fig' }->set_user( $seeduser );
  }

  ######################
  # Construct the menu #
  ######################

  my $menu = $self->application->menu();

  # Build nice tab menu here
  $menu->add_category( 'Subsystem Info', "SubsysEditor.cgi?page=ShowSubsystem&subsystem=$esc_name" );
  $menu->add_category( 'Functional Roles', "SubsysEditor.cgi?page=ShowFunctionalRoles&subsystem=$esc_name" );
  $menu->add_category( 'Diagrams and Illustrations' );
  $menu->add_entry( 'Diagrams and Illustrations', 'Diagram', "SubsysEditor.cgi?page=ShowDiagram&subsystem=$esc_name" );
  $menu->add_entry( 'Diagrams and Illustrations', 'Illustrations', "SubsysEditor.cgi?page=ShowIllustrations&subsystem=$esc_name" );
  $menu->add_category( 'Spreadsheet', "SubsysEditor.cgi?page=ShowSpreadsheet&subsystem=$esc_name" );
  $menu->add_category( 'Show Check', "SubsysEditor.cgi?page=ShowCheck&subsystem=$esc_name" );
  $menu->add_category( 'Show Connections', "SubsysEditor.cgi?page=ShowTree&subsystem=$esc_name" );
 
  
  ##############################
  # Construct the page content #
  ##############################
  my $comment;
  my $error;

  my $content = "<H1>Variants for Subsystem:  $ssname</H1>";

  if ( !defined( $name ) ) {
    $content .= "<B>No subsystem given</B>";
    return $content;
  }

  $content .= $self->start_form();

  #### 100x100 ####
  if ( defined( $self->{ 'cgi' }->param( 'on100x100' ) ) ) {
    $self->{ 'cgi' }->param( 'hundred_hundred', 1 );
  }
  if ( defined( $self->{ 'cgi' }->param( 'off100x100' ) ) ) {
    $self->{ 'cgi' }->param( 'hundred_hundred', 0 );
  }


  if ( !defined( $self->{ 'cgi' }->param( 'hundred_hundred' ) ) || $self->{ 'cgi' }->param( 'hundred_hundred' ) != 1 ) {
    $content .= $self->{ 'cgi' }->submit( -name => "on100x100", -value => "Show only 100x100" );
  }
  else {
    $content .= $self->{ 'cgi' }->submit( -name => "off100x100", -value => "Show all genomes" );
  }

  my $subsystem = $self->{ 'fig' }->get_subsystem( $name );

  my $datahash = $self->get_data( $subsystem );

  my $application = $self->application;

  if ( $self->{ 'cgi' }->param( 'set_variants' ) ) {
    $comment .= '<BR>';
    $comment .= set_variants( $self, $name, $subsystem, $application, $datahash );
    $datahash = $self->get_data( $subsystem );
  }
  elsif ( $self->{ 'cgi' }->param( 'addsave_variants' ) ) {
    my @varcodes = $self->{ 'cgi' }->param( 'VARIANT' );
    my @vardescs = $self->{ 'cgi' }->param( 'VARIANTDESC' );
    my %varhash;

    for ( my $i = 0; $i < scalar( @varcodes ); $i++ ) {

      if ( $varcodes[$i] eq '' ) {
	if ( $vardescs[$i] ne '' ) {
	  $comment .= "No Variant Code given for description ".uri_unescape( $vardescs[$i] ).", so this variant could not be saved.<BR>\n";
	}
	next;
      }
      if ( defined( $varhash{ $varcodes[$i] } ) ) {
	$comment .= "Variant ".$varcodes[$i]." already has the description ".$varhash{ $varcodes[$i] }.", so description ".uri_unescape( $vardescs[$i] )." was ignored.<BR>\n";
	next;
      }

      $varhash{ $varcodes[$i] } = uri_unescape( $vardescs[$i] );
    }
    my $newvarcode = $self->{ 'cgi' }->param( 'NEWVARIANT' );
    my $newvardesc = $self->{ 'cgi' }->param( 'NEWVARIANTDESC' );
    if ( defined( $newvarcode ) && $newvarcode ne '' && defined( $newvardesc ) && $newvardesc ne '' ) {
      if ( $newvarcode eq '' ) {
	if ( $newvarcode ne '' ) {
	  $comment .= "No Variant Code given for description ".uri_unescape( $newvardesc ).", so this variant could not be saved.<BR>\n";
	}
      }
      elsif ( defined( $varhash{ $newvarcode } ) ) {
	$comment .= "Variant $newvarcode already has the description ".uri_unescape( $newvardesc ).", so description ".uri_unescape( $newvardesc )." was ignored.<BR>\n";
      }
      else {
	$varhash{ $newvarcode } = uri_unescape( $newvardesc );
      }
    }

    $subsystem->set_variants( \%varhash );
    $subsystem->incr_version();
    $subsystem->db_sync();
    $subsystem->write_subsystem();
  }

  if ( defined( $comment ) && $comment ne '' ) {
    my $info_component = $application->component( 'CommentInfo' );
    
    $info_component->content( $comment );
    $info_component->default( 0 );
    $content .= $info_component->output();
  }    


  $content .= show_variants( $self, $name, $subsystem, $can_alter, $datahash );

  ###############################
  # Display errors and comments #
  ###############################
 
  if ( defined( $error ) && $error ne '' ) {
    $self->application->add_message( 'warning', $error );
  }
  return $content;
}

###############
# data method #
###############
sub get_data {
  my ( $self, $subsystem ) = @_;

  my $datahash = {};

  my @genomes = $subsystem->get_genomes;

  my %thesegenomes;

  if ( defined( $self->{ 'cgi' }->param( 'hundred_hundred' ) ) && $self->{ 'cgi' }->param( 'hundred_hundred' ) == 1 ) {
    my %orgs = map { $_->[0] => 1 } grep { $_->[0] =~ /^\d+\.\d+$/ } $self->{ 'fig' }->get_attributes( undef, 'collection', 'hundred_hundred' );

    foreach my $g ( @genomes ) {
      if ( defined( $orgs{ $g } ) ) {
	$thesegenomes{ $g } = 1;
      }
    }
    @genomes = keys %thesegenomes;
  }

  my %variant_codes = map { $_ => $subsystem->get_variant_code( $subsystem->get_genome_index( $_ ) ) } @genomes;
  my @roles          = $subsystem->get_roles;

  $datahash->{ 'genomes' } = \@genomes;
  $datahash->{ 'varcodes' } = \%variant_codes;
  $datahash->{ 'roles' } = \@roles;  
  
  return $datahash;
}

#########################################################
# show table with variants and button for changing them #
#########################################################
sub show_variants {
  my ( $self, $name, $sub, $can_alter, $datahash ) = @_;

  my $application = $self->application();

  my $cont = '';

  # get some datapoints #
  my @genomes        = @{ $datahash->{ 'genomes' } };
  my %variant_codes = %{ $datahash->{ 'varcodes' } };
  my @roles          = @{ $datahash->{ 'roles' } };
  
  my ( $abbrev, $frtable ) = $self->format_roles( $sub );
  
  my( @has, $role, %has_filled );
  foreach my $genome ( @genomes ) {
    @has = ();
    foreach $role (@roles)
      {
	push(@has,($sub->get_pegs_from_cell($genome,$role) > 0) ? $abbrev->{$role} : ());
      }
    $has_filled{join(",",@has)}->{$variant_codes{$genome}}++;
  }
  
  my ( $col_hdrs, $pattern_uq );
  if ( $can_alter ) {
    $col_hdrs = [ { name => "Pattern" }, { name => "# Genomes with Pattern" },
		  { name => "Existing Variant Code" }, { name => "Set To" } ];
  }
  else {
    $col_hdrs = [ { name => "Pattern" }, { name => "# Genomes with Pattern" },
		  { name => "Existing Variant Code" } ];
  }

  my $tab = [];
  foreach $pattern_uq ( sort keys( %has_filled ) ) {

    my $pattern = quotemeta( $pattern_uq );

    my @codes = keys( %{ $has_filled{ $pattern_uq } } );
    my $code;
    my $nrow = @codes;
    if ( @codes > 0 ) {
      $code = shift @codes;
      if ( $can_alter ) {
	push( @$tab, [ $pattern_uq,
		       $has_filled{ $pattern_uq }->{ $code },
		       $code,		     
		       $self->{ 'cgi' }->textfield(-name => "p##:##$pattern##:##$code", -size => 5, -value => $code, -override => 1)
		     ]);
      }
      else {
	push( @$tab, [ $pattern_uq,
		       $has_filled{ $pattern_uq }->{ $code },
		       $code
		     ]);
      }
    }
        
    foreach $code ( @codes ) {
      if ( $can_alter ) {
	push( @$tab, [ $pattern_uq, 
		       $has_filled{ $pattern_uq }->{ $code },
		       $code,
		       $self->{ 'cgi' }->textfield( -name => "p##:##$pattern##:##$code", -size => 5, -value => $code, -override => 1)
		     ]);
      }
      else {
	push( @$tab, [ $pattern_uq, 
		       $has_filled{ $pattern_uq }->{ $code },
		       $code
		     ]);
      }
    }
  }

  $cont .= $frtable;
  
  my $thistable = create_table( $self, \%has_filled, $col_hdrs, $tab );

  ############################################
  # Variant Descriptions from the Notes file #
  ############################################
  $cont .= "<H2>Variant descriptions</H2>\n";
  my $variants = $sub->get_variants();

  my $infotable = '';
  if ( $can_alter ) {
    $infotable .= "<TABLE class='table_table'><TR><TD class='table_first_row'>Variant</TD><TD class='table_first_row'>Description</TD></TR>";
    foreach my $kv ( sort keys %$variants ) {
      my $esc_kvd = $variants->{ $kv };
      $esc_kvd =~ s/'/&#39;/g;
      $infotable .= "<TR><TD class='table_odd_row'>";
      $infotable .= $self->{ 'cgi' }->textfield( -name => "VARIANT", -id => "VARIANT", -size => 20, -value => $kv, -override => 1 );
      $infotable .= "</TD><TD class='table_odd_row'>";
      $infotable .= $self->{ 'cgi' }->textfield( -name => "VARIANTDESC", -id => "VARIANTDESC", -size => 70, -value => $variants->{ $kv }, -override => 1 );
      $infotable .= "</TD></TR>";
    }
    $infotable .= "<TR><TD class='table_odd_row'>";
    $infotable .= $self->{ 'cgi' }->textfield( -name => "NEWVARIANT", -id => "NEWVARIANT", -size => 20, -override => 1 );
    $infotable .= "</TD><TD class='table_odd_row'>";
    $infotable .= $self->{ 'cgi' }->textfield( -name => "NEWVARIANTDESC", -id => "NEWVARIANTDESC", -size => 70, -override => 1 );
    $infotable .= "</TD></TR>";
    $infotable .= "<TR><TD>";
    $infotable .= $self->{ 'cgi' }->submit( -name => "addsave_variants", -value => "Add/Save Variants" );
    $infotable .= "</TD></TR></TABLE>";

    $cont .= $infotable;
  }
  else {
    my $infotable = $application->component( 'VarDescTable' );
    $infotable->columns( [ { name => "Variant" }, { name => "Description" } ] );

    my $vardata;
    foreach my $kv ( sort keys %$variants ) {
      push @$vardata, [ $kv, $variants->{ $kv } ];
    }
    $infotable->data( $vardata );
    $cont .= $infotable->output();
  } 

  my $esc_name = uri_escape($name);

  $cont .= "<H2>Variant groups</H2>\n";
  $cont .= $thistable;
  
  $cont .= $self->{ 'cgi' }->hidden(-name => 'request', -value => 'set_variants', -override => 1);
  $cont .= $self->{ 'cgi' }->hidden(-name => 'subsystem', -value => $name, -override => 1 );

  if ( defined( $self->{ 'cgi' }->param( 'hundred_hundred' ) ) ) {
    $cont .= $self->{ 'cgi' }->hidden(-name => 'hundred_hundred', -value => $self->{ 'cgi' }->param( 'hundred_hundred' ), -override => 1 );
  }

  if ( $can_alter ) {
    $cont .= $self->{ 'cgi' }->br;
  }
  $cont .= $self->{ 'cgi' }->submit( -name => "set_variants", -value => "Set Variants" );
  $cont .= $self->end_form();
  
  return $cont;
}
	    

###############################
# get a functional role table #
###############################
sub format_roles {
    my( $self, $subsystem ) = @_;
    my( $i );

    my $col_hdrs = [ "Column", "Abbrev", "Functional Role" ];

    my ( $tab, $abbrevP ) = $self->format_existing_roles( $subsystem );

    # create table from parsed data
    my $table = $self->application->component( 'FRTable' );
    $table->columns( $col_hdrs );
    $table->data( $tab );

    my $formatted = '<H2>Functional Roles</H2>';
    $formatted .= $self->application->component( 'FRTable' )->output();

    $formatted .= "<BR><BR>";
    return ( $abbrevP, $formatted );
}

#########################################
# get rows of the functional role table #
#########################################
sub format_existing_roles {
    my ( $self, $subsystem ) = @_;
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


##############################################
# change the variants in the subsystems file #
##############################################
sub set_variants {
    my ( $self, $subsys, $sub, $application, $datahash ) = @_;

    my @genomes        = @{ $datahash->{ 'genomes' } };
    my %variant_codes = %{ $datahash->{ 'varcodes' } };
    my @roles          = @{ $datahash->{ 'roles' } };

    my ( $abbrev, $frtable ) = $self->format_roles( $sub );

    my ( %genomes_with );
    foreach my $genome ( @genomes ) {
      my $vc = $variant_codes{ $genome };
      
      my @has = ();
      foreach my $role ( @roles ) {
	push( @has, ( $sub->get_pegs_from_cell( $genome, $role ) > 0 ) ? $abbrev->{ $role } : () );
      }
      my $pattern = quotemeta( join( ",", @has ) );
      push( @{ $genomes_with{ "$pattern, $vc" } }, $genome );
    }

    my $comment = '';
    my @params = grep { $_ =~ /^p##:##/ } $self->{ 'cgi' }->param;

    foreach my $param (@params) {

      if ( $param =~ /^p##:##(.*)##:##(.*)$/ ) {
	my ( $pattern, $vc ) = ( $1, $2 );

	$pattern =~ s/ //g;
	$vc      =~ s/ //g;
	my $to = $self->{ 'cgi' }->param( $param );

	if ( my $x = $genomes_with{ "$pattern, $vc" } ) {
	  foreach my $genome ( @$x ) {

	    if ( $to ne $variant_codes{ $genome } ) {

	      my $old = $variant_codes{$genome};
	      my $gs = $self->{ 'fig' }->genus_species( $genome );
	      $comment .= "resetting $genome $gs from $old to $to<BR>\n";
	      $sub->set_variant_code( $sub->get_genome_index( $genome ), $to );
	    }
	  }
	}
      }
    }

    $sub->incr_version();
    $sub->db_sync();
    $sub->write_subsystem();

    return $comment;
}

sub create_table {
  my ( $self, $has_filled, $col_hdrs, $tab ) = @_;

  my $in;
  my $tabl = "<TABLE class='table_table'><TR>";

  foreach my $ch ( @$col_hdrs ) {
    $tabl .= "<TD class='table_first_row'>";
    $tabl .= $ch->{ name };
    $tabl .= "</TD>";
  }

  foreach my $r ( @$tab ) {
    $tabl .= "<TR>";

    my $num = scalar( keys %{ $has_filled->{ $r->[0] } } );
    my $pat = $r->[0];
    if ( $num > 1 ) {
      if ( !$in->{ $pat } ) {
	$tabl .= "<TD rowspan=$num class='table_odd_row' STYLE='vertical-align: middle;'>".$r->[0]."</TD>";
	$in->{ $pat } = 1;
      }
    }
    else {
      $tabl .= "<TD class='table_odd_row'>".$r->[0]."</TD>";
    }
    my $next = 0;
    foreach my $cell ( @$r ) {
      if ( $next == 0 ) {
	$next = 1;
	next;
      }
      else {
	$tabl .= "<TD class='table_odd_row'>".$cell."</TD>";
      }
    }
    $tabl .= "</TR>";
  }

  $tabl .= "</TABLE>";

  return $tabl;
}
