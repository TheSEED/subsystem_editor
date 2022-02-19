package SubsystemEditor::WebPage::MissingWithMatches;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;

use FIG;

use base qw( WebPage );

1;

##############################################################
# Method for registering components etc. for the application #
##############################################################
sub init {
  my ( $self ) = @_;
  $self->application->register_component( 'Hover', 'TableHoverComponent' );
  $self->application->register_component( 'Info', 'CommentInfo');
}

#################################
# File where Javascript resides #
#################################
sub require_javascript {

  return [ './Html/showfunctionalroles.js' ];

}

##############################################
# Website content is returned by this method #
##############################################
sub output {
  my ( $self ) = @_;

  my $fig = new FIG;
  my $cgi = $self->application->cgi;
  
  # subsystem name and 'nice name' #
  my $name = $cgi->param( 'subsystem' );

  if ( !defined( $name ) ) {
    return $self->application->add_message( 'warning', "No subsystem given\n" );
  }

  my $ssname = $name;
  $ssname =~ s/\_/ /g;


  my @srs = $cgi->param( 'fr' );
  my %showroles = map { $_ => 1 } @srs;

  my @sg = $cgi->param( 'genome' );
  my @showgenomes = ();
  foreach my $sge ( @sg ) {
    if ( $sge =~ /genome\_checkbox\_(.*)/ ) {
      $sge = $1;
    }
    push @showgenomes, $sge;
  }

  # look if someone is logged in and can write the subsystem #
  my $can_alter = 0;
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

  if ( $user ) {
    if ( $user->has_right( $self->application, 'edit', 'subsystem', $name ) ) {
      $can_alter = 1;
      $fig->set_user( $seeduser );
    }
  }

  my $subsystem = new Subsystem( $name, $fig, 0 );

  my ( $error, $comment ) = ( "", "" );

  #########
  # TASKS #
  #########

  my $processed = 0;
  if ( defined( $cgi->param( 'ProcessAssignments' ) ) ) {
    my @to_pegs = $cgi->param( 'checked' );

    my ( $putcomment, $puterror ) = put_pegs_into_spreadsheet( $fig, $subsystem, \@to_pegs, $seeduser );
    $error .= $puterror;
    $comment .= $putcomment;
#    $subsystem = new Subsystem( $name, $fig, 0 );
    $processed = 1;
  }

  ##############################
  # Construct the page content #
  ##############################
 
  my $content = qq~
<STYLE>
.hideme {
   display: none;
}
.showme {
   display: all;
}
</STYLE>
~;
$content .= "<STYLE>td {border: 1px solid black; padding: 3px; font-size: 10pt} table {border-spacing: 0px; } body {font-family: Helvetica; font-size: 10pt;} th {border: 1px solid black; padding: 3px; font-size: 10pt}</STYLE><BR>";
  $content .= "<H1>Show missing with matches for subsystem $ssname</H1>";
  if ( !$processed ) {
    $content .= "<P>This table shows all genomes in the spreadsheet that might miss pegs. The missing pegs are found by similarity to pegs from other genomes already present in the spreadsheet.</P><P><B>Hover</B> over the suggested pegs to get the similarity information. If you select suggested pegs and click <B>'Process assignments'</B>, these pegs will be annotated and directly put into the spreadsheet.</P>";
  }    

  if ( defined( $comment ) && $comment ne '' ) {
    my $info_component = $self->application->component( 'CommentInfo' );
    
    $info_component->content( $comment );
    $info_component->default( 0 );
    $content .= $info_component->output();
  } 

  if ( !$processed ) {
    $content .= $self->start_form( 'form', { subsystem => $name,
					     fr        => \@srs, 
					     genome    => \@sg } );
    $content .= $cgi->submit( -value => "Process assignments",
			      -name => "ProcessAssignments" );
    
    my ( $datahash, $subsetC ) = &format_missing_including_matches( $fig, $cgi, \%showroles, \@showgenomes, $subsystem, $seeduser, $can_alter );
    
    my $bgcolor;
    my $i = 0;
    my $table = "<TABLE><TR><TH>Genome</TH>";
    my $hover_component = $self->application->component( 'TableHoverComponent' );
    
    foreach my $role ( @$subsetC ) {
      my $abk = $subsystem->get_role_abbr( $subsystem->get_role_index( $role ) );
      my $abk_header = "<SPAN STYLE='white-space: nowrap;' onmouseover='hover(event, \"hover_test_".$abk."\");'>".$abk."</SPAN>";
      $table .= "<TH>$abk_header</TH>";
      $hover_component->add_tooltip( 'hover_test_'.$abk, $role );
    }
    $table .= "</TR>\n";
    
    foreach my $g ( keys %$datahash ) {
      $i++;
      if ( $i % 2 ) {
	$bgcolor = '#ababeb';
      }
      else {
	$bgcolor = '#FFFFFF';
      }
      
      my $tab = get_table( $self, $datahash->{ $g }->{ 'pegs' }, $g, $datahash->{ $g }->{ 'genus_species' }, $subsystem, $subsetC, $can_alter, $bgcolor, $seeduser );
      $table .= $tab;
    } 
    $table .= "</TABLE>";
    
    $content .= $table;
    
    $content .= $cgi->submit( -value => "Process assignments",
			      -name => "ProcessAssignments" );
    
    $content .= $self->end_form();
    
    $content .= $hover_component->output();
  }

  else {
    $content .= $self->start_form( 'form', { subsystem => $name,
					     fr        => \@srs, 
					     genome    => \@sg } );
    $content .= $cgi->submit( -value => "Compute missing with matches again" );
  }
  
  ###############################
  # Display errors and comments #
  ###############################
  
  if ( defined( $error ) && $error ne '' ) {
    $self->application->add_message( 'warning', $error );
  }
  
  return $content;
}

sub supported_rights {
  
  return [ [ 'edit', 'subsystem', '*' ] ];
  
}

sub get_table {
  my ( $self, $pegshash, $org, $genusspecies, $subsystem, $subsetC, $can_alter, $bgcolor, $seeduser ) = @_;

  my $hover_component = $self->application->component( 'TableHoverComponent' );
  my $oldhash;
  my $newhash;
  my $i = 0;
  
  foreach my $role ( @$subsetC ) {
    
    my @ps = $subsystem->get_pegs_from_cell( $org, $role );
    $oldhash->{ $role } = \@ps; 
    my @newps;
    foreach my $p ( keys %$pegshash ) {

      my @splitrole = split( ' / ', $pegshash->{ $p }->{ 'match_fn' } );
      if ( scalar( @splitrole ) < 2 ) {
	my @splitrole = split( ' @ ', $pegshash->{ $p }->{ 'match_fn' } );
      }
      if ( scalar( @splitrole ) < 2 ) {
	my @splitrole = split( ' ; ', $pegshash->{ $p }->{ 'match_fn' } );
      }
      
      foreach my $sr ( @splitrole ) {
	if ( $sr eq $role ) {
	  push @newps, $p;
	}
      }
    }
    $newhash->{ $role } = \@newps; 
  }
  my $table = "<TR bgcolor='$bgcolor'><TD><B>$genusspecies ($org)</B></TD>";
  my $end = '';
  
  # what's in goes here
  foreach my $role ( @$subsetC ) {
    $i++;
    $table .= "<TD>";
    
    my @ops;
    foreach my $op ( @{ $oldhash->{ $role } } ) {
      $op =~ /fig\|\d+\.\d+\.peg\.(\d+)/;
      my $on = $1;
      my $oplink = &fid_link( $op, $seeduser );
      $oplink = "<A HREF='$oplink' target=_blank>$on</A>";

      push @ops, $oplink;
    }
    
    $table .= ( join( ',', @ops ) || '-' );
    $table .= "</TD>";
    $end .= "<TD>";
    my $infor = 0;
    foreach my $p ( @{ $newhash->{ $role } } ) {
      
      # create hover text #
      my $ht = "<TABLE><TR><TD>Matched Peg:</TD><TD>".$pegshash->{ $p }->{ 'match_peg' }."</TD></TR>";
      $ht .= "<TR><TD>Match PScore:</TD><TD>".$pegshash->{ $p }->{ 'evalue' }."</TD></TR>";
      $ht .= "<TR><TD>Matched Peg Length:</TD><TD>".$pegshash->{ $p }->{ 'match_len' }."</TD></TR>";
      $ht .= "<TR><TD>To Function:</TD><TD>".$pegshash->{ $p }->{ 'match_fn' }."</TD></TR>";
      $ht .= "<TR><TD>This Peg Length:</TD><TD>".$pegshash->{ $p }->{ 'length' }."</TD></TR>";
      $ht .= "<TR><TD>This Peg Function:</TD><TD>".$pegshash->{ $p }->{ 'function' }."</TD></TR>";
      $ht .= "<TR><TD>Clustered With Genes in SS:</TD><TD>".( join( ', ', @{ $pegshash->{ $p }->{ 'clustered_with' } } ) || '-' )."</TD></TR>";
      $ht .= "</TABLE>";

      $hover_component->add_tooltip( 'hover_test_'.$p.'_'.$i, $ht );

      $p =~ /fig\|\d+\.\d+\.peg\.(\d+)/;
      my $n = $1;
      my $plink = &fid_link( $p, $seeduser );
      $plink = "<A HREF='$plink' target=_blank>$n</A>";

      if ( $can_alter ) {
	$end .= "<SPAN STYLE='white-space: nowrap;' onmouseover='hover(event, \"hover_test_".$p."_".$i."\");'>".$pegshash->{ $p }->{ 'checkbox' }.$plink."</SPAN>";
	$end .= " ";
      }
      else {
	$end .= "<SPAN STYLE='white-space: nowrap;' onmouseover='hover(event, \"hover_test_".$p."_".$i."\");'>".$plink."</SPAN>";
	$end .= " ";
      }

      if ( defined( $end ) ) {
	$infor = 1;
      }
    }
    unless ( $infor ) {
      $end .= '-';
    }
    
    $end .= "</TD>\n";
  }
  $table .= "</TR><TR bgcolor='$bgcolor'><TD>ToPutIn</TD>".$end."</TR>";
  
  return $table;
}


sub format_missing_including_matches {
  my( $fig, $cgi, $showroles, $showgenomes, $subsystem, $seeduser, $can_alter ) = @_;
  
  my $datahash = {};

  my @subsetC = $subsystem->get_roles();

  my %activeC;
  if ( defined( $showroles ) && scalar( keys %$showroles ) > 0 ) {
    foreach my $abk ( keys %$showroles ) {
      my $r = $subsystem->get_role_from_abbr( $abk );
      $activeC{ $r } = 1;
    }
  }
  else {
    %activeC = map { $_ => 1 } @subsetC;
  }
  @subsetC = keys %activeC;

  my @subsetR = $subsystem->get_genomes();

  if ( defined( $showgenomes ) && scalar( @$showgenomes ) > 0) {
    @subsetR = @$showgenomes;
  }
  
  my %in;
  foreach my $set ( grep { ($_ =~ /^\*/) } sort $subsystem->get_subset_namesC ) {
    foreach my $col ( grep { $activeC{ $_ } } $subsystem->get_subsetC_roles($set) ) {
      $in{ $col } = $set;
    }
  }
  
  my $missing;
  my @pegsInSS = $subsystem->get_all_pegs();

  foreach my $org (@subsetR) {

    my $loc;
    my $raworg = $org;
    if ( $org =~ /(\d+\.\d+)\:(.*)/ ) {
      $raworg = $1;
      $loc = $2;
    }

    my @missing = &columns_missing_entries( $cgi, $subsystem, $org, \@subsetC, \%in );
    $missing = [];
    foreach my $role (@missing) {
      my @hits = $fig->find_role_in_org( $role, $raworg, $seeduser, $cgi->param( "sims_cutoff" ) );
      foreach my $h ( @hits ) {
	push( @$missing, [ $h, $role ] );
      }
    }
    
    if ( @$missing > 0 ) {
      my $genus_species = &ext_genus_species( $fig, $raworg );
      
      foreach my $hitarr ( @$missing ) {
	my ( $psc, $my_peg, $my_len, $my_fn, $match_peg, $match_len, $match_fn ) = @{ $hitarr->[0] };

	if ( defined( $loc ) ) {
	  my ( $contig_reg, $beg_reg, $end_reg ) = $fig->boundaries_of( $loc );

	  my $loc_hit = $fig->feature_location( $my_peg );
	  my ( $contig_hit, $beg_hit, $end_hit ) = $fig->boundaries_of( $loc_hit );

	  next if ( $contig_reg ne $contig_hit );
	  next if ( $beg_reg > $beg_hit );
	  next if ( $end_reg < $end_hit );
	}
	
	# get the clustered genes for this peg #
	my %close = map { $_ => 1 }  $fig->close_genes( $my_peg, 4000 );
	my @cw = grep { $close{ $_ } } @pegsInSS;
	my @clustered_with;
	foreach my $c ( @cw ) {
	  $c =~ /fig\|\d+\.\d+\.peg\.(\d+)/;
	  my $n = $1;
	  push @clustered_with, $n;
	}
	
	my $checkbox = $cgi->checkbox(-name => "checked",
				      -value => "to=$my_peg,from=$match_peg,role=".$hitarr->[1],
				      -label => "");
	
	$datahash->{ $org }->{ 'genus_species' } = $genus_species;
	$datahash->{ $org }->{ 'pegs' }->{ $my_peg } = { 'checkbox'       => $checkbox,
							 'evalue'         => $psc,
							 'length'         => $my_len,
							 'function'       => $my_fn,
							 'match_peg'      => $match_peg,
							 'match_len'      => $match_len,
							 'match_fn'       => $match_fn,
							 'clustered_with' => \@clustered_with };
      }
    }
  }
  return ( $datahash, \@subsetC );
}


######################################################################
# this function gets all columns for a combination of subsystem and  #
# role that are empty, and where all roles of the subset are as well #
######################################################################
sub columns_missing_entries {
  my ( $cgi, $subsystem, $org, $roles, $in ) = @_;
  
  my ( @really_missing ) = ();
  
  # get all potential missing cells #
  my %missing_cols;
  foreach my $role ( @$roles ) {
    if ( $subsystem->get_pegs_from_cell( $org, $role ) == 0 ) {
      $missing_cols{ $role } = 1;
    }
  }
  
  # filter the ones out that have a peg member in its subset #
  foreach my $role ( @$roles ) {
    if ( $missing_cols{ $role } ) {
      if ( ( my $set = $in->{ $role } ) && ( ! $cgi->param( 'ignore_alt' ) ) ) {
	my @set = $subsystem->get_subsetC_roles( $set );
	
	my $k;
	for ( $k = 0; ( $k < @set ) && $missing_cols{ $set[$k] }; $k++ ) {}
	if ( $k == @set ) {
	  push( @really_missing, $role );
	}
      }
      else {
	push( @really_missing, $role );
      }
    }
  }
  return @really_missing;
}



sub put_pegs_into_spreadsheet {

  my ( $fig, $subsystem, $pegs, $seeduser ) = @_;

  my ( $comment, $error ) = ( '', '' );
  
  foreach my $ent ( @$pegs ) {

    if ( $ent =~ /^to=(.*),from=(.*),role=(.*)$/ ) {
      my $to_peg = $1;
      my $from_peg = $2;
      my $role = $3;
      
      my $from_func = $fig->function_of( $from_peg );
      
      next unless $from_func;

      if ( $fig->assign_function( $to_peg, $seeduser, $from_func, "" ) ) {
	$comment .= "Set master function of $from_peg to\n$from_func <BR>\n";

	my $genome = $fig->genome_of( $to_peg );
	
	# get pegs from corresponding cell #
	my @cellpegs = $subsystem->get_pegs_from_cell( $genome, $role );
	
	# check if it's already in there #
	my $alreadyin = 0;
	foreach my $p ( @cellpegs ) {
	  if ( $p eq $to_peg ) {
	    $alreadyin = 1;
	    $error .= "CDS $to_peg is already in the subsystem.<BR>\n";
	  }
	}
	
	# if not put it in #
	if ( !$alreadyin ) {
	  push @cellpegs, $to_peg;
	}
	
	# set pegs for cell #
	$subsystem->set_pegs_in_cell( $genome, $role, \@cellpegs );
	
	$comment .= "Added CDS $to_peg to the subsystem.<BR>\n";
	
      }
      else {
	$error .= "Error assigning $from_func to $to_peg.<BR>\n";
      }
    }
  }

  # write spreadsheet #
  $subsystem->db_sync();
  $subsystem->write_subsystem();

  return ( $comment, $error );
}


sub ext_genus_species {
  my( $fig, $genome ) = @_;
  
  my ( $gs, $c ) = $fig->genus_species_domain( $genome );
  $c = ( $c =~ m/^Environ/i ) ? 'M' : substr($c, 0, 1);  # M for metagenomic
  return "$gs [$c]";
}

sub fid_link {
  my ( $fid, $seeduser ) = @_;
  my $n;
  
  if ($fid =~ /^fig\|\d+\.\d+\.([a-zA-Z]+)\.(\d+)/) {
    if ( $1 eq "peg" ) {
      $n = $2;
    }
    else {
      $n = "$1.$2";
    }
  }
  
#  return "./protein.cgi?prot=$fid&user=$seeduser\&new_framework=0";
  return qq~./seedviewer.cgi?page=Annotation&feature=$fid&user=$seeduser~;
}
