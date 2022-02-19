package SubsystemEditor::WebPage::ShowCheck;

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

  $self->application->register_component(  'Table', 'mmtable'  );
  $self->application->register_component(  'Table', 'adtable'  );
  $self->application->register_component(  'Table', 'gatable'  );
}

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
  my $ssname = $name;
  $ssname =~ s/\_/ /g;

  my $subsystem = new Subsystem( $name, $fig, 0 );

  my $esc_name = uri_escape($name);

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

  if ( $user && $user->has_right( $self->application, 'edit', 'subsystem', $name ) ) {
    $can_alter = 1;
    $fig->set_user( $seeduser );
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
  $menu->add_category( 'Illustrations', "SubsysEditor.cgi?page=ShowIllustrations&subsystem=$esc_name" );
  $menu->add_category( 'Spreadsheet', "SubsysEditor.cgi?page=ShowSpreadsheet&subsystem=$esc_name" );
  $menu->add_category( 'Show Check', "SubsysEditor.cgi?page=ShowCheck&subsystem=$esc_name" );
  $menu->add_category( 'Show Connections', "SubsysEditor.cgi?page=ShowTree&subsystem=$esc_name" );
 

  ##############################
  # Construct the page content #
  ##############################

  my $content = "<H1>Subsystem Check for Subsystem:  $ssname</H1>";

  $content .= get_check_data( $self, $can_alter, $fig, $cgi, $name, $user, $seeduser );

  return $content;
}


sub get_check_data {

  my ( $self, $can_alter, $fig, $cgi, $name, $user, $seeduser ) = @_;

  my $application = $self->application();

  # variables #
  my $datahash;
  my $content = '';
  my $comment = '';
  my $error = '';

  # parameter if file should be read or check should be on the fly
  my $checkonthefly = $cgi->param( 'CHECKONTHEFLY' );

     ############# 
  #### FUNCTIONS ####
     #############

  # add pegs that should be in the ss but aren't #
  if ( $cgi->param( 'ADDPEGSLEFTOUT' ) ) {
    my @pegIdChecks = $cgi->param( 'adcheckbox' );
    my ( $putcomment, $puterror ) = add_pegs_to_subsystem( $fig, $name, \@pegIdChecks );
    $comment .= $putcomment;
    $error .= $puterror;
    $checkonthefly = 1;
  }

  # remove pegs that are in the ss but shouldn't #
  if ( $cgi->param( 'REMOVEFROMSS' ) ) {
    my @pegIdChecks = $cgi->param( 'mmcheckbox' );
    my ( $putcomment, $puterror ) = remove_pegs_from_subsystem( $fig, $name, \@pegIdChecks );
    $comment .= $putcomment;
    $error .= $puterror;
    $checkonthefly = 1;
  }

  # assign the right roles to pegs that are in the ss but have the wrong role #
  if ( $cgi->param( 'ASSIGNROLES' ) ) {
    my @pegIdChecks = $cgi->param( 'mmcheckbox' );
    my ( $putcomment, $puterror ) = assign_roles_to_pegs( $fig, $name, \@pegIdChecks, $seeduser );
    $comment .= $putcomment;
    $error .= $puterror;
    $checkonthefly = 1;
  }

  # put genomes into subsystem
  if ( $cgi->param( 'ADDGENOMES' ) ) {
    my @genomes = $cgi->param( 'gacheckbox' );
    my ( $putcomment, $puterror ) = add_genomes_to_subsystem( $fig, $name, \@genomes );
    $comment .= $putcomment;
    $error .= $puterror;
    $checkonthefly = 1;
  }

  # get data from file or on the fly #
  if ( $checkonthefly ) {
    ( $datahash ) = checkdata_function( $fig, $name );
  }
  else {
    ( $datahash ) = get_data( $fig, $name );
  }

  # get last check time #
  my $lastchecktime = $datahash->{ 'lastchecktime' };
  if ( $checkonthefly ) {
    $lastchecktime = "<B>Performed check just now</B>";
  }
  elsif ( defined( $lastchecktime ) ) {
    $lastchecktime = "<B>Last check was on $lastchecktime</B>";
  }

  # get the tables for mismatch, leftout and genomes to add #
  my $succmm = $self->make_mismatch_table( $fig, $cgi, $user, $can_alter, $name, $application, $datahash );
  my $succad = $self->make_leftout_table( $fig, $cgi, $user, $can_alter, $name, $application, $datahash );  
  my $succga = make_maybeadd_table( $fig, $cgi, $can_alter, $name, $application, $datahash );  

  # print content here #
  $content .= $self->start_form( 'myform', { subsystem => $name } );
  $content .= "<H2>Subsystem Check Overview</H2>";
  $content .= "<TABLE><TR><TD COLSPAN=2>";
  $content .= "$lastchecktime";
  $content .= "</TD></TR><TR><TD COLSPAN=2>";
  $content .= "<INPUT TYPE=SUBMIT VALUE='Check subsystem data on the fly' NAME='CHECKONTHEFLY' ID='CHECKONTHEFLY' >";

  if ( $lastchecktime ) {
    $content .= "</TD></TR><TR><TD>";
    $content .= $datahash->{ 'mismatchesN' };
    $content .= "</TD><TD>";
    $content .= "entries mismatch the role";
    $content .= "</TD></TR><TR><TD>";
    $content .= $datahash->{ 'leftoutN' };
    $content .= "</TD><TD>";
    $content .= "entries should be added for existing genomes";
    $content .= "</TD></TR><TR><TD>";
    $content .= $datahash->{ 'maybeaddN' };
    $content .= "</TD><TD>";
    $content .= "genomes maybe should be added";
  }
  else {
    $content .= "<BR><BR>No check available";
  }
  $content .= "</TD></TR></TABLE>";
  
  
  if ( $lastchecktime ) {
    if ( $succmm ) {
      $content .= "<H2>CDSs IN Subsystem with MISMATCHING Functions</H2>";
      $content .= $application->component( 'mmtable' )->output();
      if ( $can_alter ) {
	$content .= "<TABLE><TR><TD>";
	$content .= "<INPUT TYPE=SUBMIT VALUE='Assign Roles to Selected CDSs' ID='ASSIGNROLES' NAME='ASSIGNROLES'>";
	$content .= "</TD><TD>";
	$content .= "<INPUT TYPE=SUBMIT VALUE='Remove Selected CDSs from Subsystem' ID='REMOVEFROMSS' NAME='REMOVEFROMSS'>";

	my ( $cab, $ucab ) = getCheckButtons( 'mmcheckbox' );
	$content .= "</TD><TD>";
	$content .= $cab;
	$content .= "</TD><TD>";
	$content .= $ucab;
	$content .= "</TD></TR></TABLE>";
      }
    }
    if ( $succad ) {
      $content .= "<H2>CDSs NOT in Subsystem with MATCHING Functions</H2>";
      $content .= $application->component( 'adtable' )->output();
      if ( $can_alter ) {
	$content .= "<TABLE><TR><TD>";
	$content .= "<INPUT TYPE=SUBMIT VALUE='Add selected features to my subsystem' ID='ADDPEGSLEFTOUT' NAME='ADDPEGSLEFTOUT'>";

	my ( $cab, $ucab ) = getCheckButtons( 'adcheckbox' );
	$content .= "</TD><TD>";
	$content .= $cab;
	$content .= "</TD><TD>";
	$content .= $ucab;
	$content .= "</TD></TR></TABLE>";
      }
    }
    if ( $succga ) {
      $content .= "<H2>Genomes that could maybe be added to the subsystem</H2>";
      $content .= $application->component( 'gatable' )->output();      
      if ( $can_alter ) {
	$content .= "<TABLE><TR><TD>";
	$content .= "<INPUT TYPE=SUBMIT VALUE='Add selected genomes to my subsystem' ID='ADDGENOMES' NAME='ADDGENOMES'>";

	my ( $cab, $ucab ) = getCheckButtons( 'gacheckbox' );
	$content .= "</TD><TD>";
	$content .= $cab;
	$content .= "</TD><TD>";
	$content .= $ucab;
	$content .= "</TD></TR></TABLE>";
      }
    }
  }
  $content .= $self->end_form();

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

######################################
# assign the pegs with the new roles #
######################################
sub assign_roles_to_pegs {

  my ( $fig, $name, $addpegs, $curator ) = @_;

  my $subsystem = new Subsystem( $name, $fig, 0 );
  my $comment = '';
  my $error = '';

  # go through checked pegs #
  foreach my $pegn ( @$addpegs ) {

    # get peg and role #
    $pegn =~ /^mmcheckbox\_(.*)\_to\_(.*)/;
    my $peg = $1;
    my $role = $2;
    my $function = $fig->function_of( $peg );
    my $genome = $fig->genome_of( $peg );
    
    # assign the function #
    if ( $fig->assign_function( $peg, $curator, $role, "" ) ) {
	$comment = "Sucessfully set annotation of $peg to $role\n";
    }
    else {
      $error = "Could not assign annotation of $peg to $role\n";
    }
  }
  return ( $comment, $error );
  
}

##############################
# remove pegs from subsystem #
##############################
sub remove_pegs_from_subsystem {

  my ( $fig, $name, $addpegs ) = @_;

  my $subsystem = new Subsystem( $name, $fig, 0 );
  my $comment = '';
  my $error = '';

  # go through checked pegs #
  foreach my $pegn ( @$addpegs ) {

    # get peg and role #
    $pegn =~ /^mmcheckbox\_(.*)\_to\_(.*)/;
    my $peg = $1;
    my $role = $2;
    my $function = $fig->function_of( $peg );
    my $genome = $fig->genome_of( $peg );

    # get pegs from corresponding cell, and remove our peg from that list #
    my @pegs = $subsystem->get_pegs_from_cell( $genome, $role );
    my @newpegs;
    my $alreadyin = 0;
    foreach my $p ( @pegs ) {
      unless ( $p eq $peg ) {
	push @newpegs, $p;
      }
    }

    # set the list without the deleted peg
    my $success = $subsystem->set_pegs_in_cell( $genome, $role, \@newpegs );
    if ( !defined( $success ) ) {
      $error = "Cannot remove CDS $peg as it is not in the subsystem<BR>\n;";
    }

    $comment .= "Removed CDS $peg from the subsystem<BR>\n";
  }

  # write spreadsheet #
  $subsystem->db_sync();
  $subsystem->write_subsystem();

  return ( $comment, $error );

}

#############################
# add pegs to the subsystem #
#############################
sub add_pegs_to_subsystem {

  my ( $fig, $name, $addpegs ) = @_;

  my $subsystem = new Subsystem( $name, $fig, 0 );
  my $comment = '';
  my $error = '';

  # get peg and role #
  foreach my $pegn ( @$addpegs ) {
    my($peg, $role) = $pegn =~ /^adcheckbox_(fig\|\d+\.\d+\.peg\.\d+)\_(.*)/;
    if (!$peg)
    {
	print STDERR "Skipping non-peg $pegn\n";
	next;
    }
    $role =~ s/\_/ /g;
    print STDERR $pegn."\n";
print STDERR $role . " ROLE\n";
#    my $role = $fig->function_of( $peg );
    my $genome = $fig->genome_of( $peg );

    # get pegs from corresponding cell #
    my @pegs = $subsystem->get_pegs_from_cell( $genome, $role );

    # check if it's already in there #
    my $alreadyin = 0;
    foreach my $p ( @pegs ) {
      if ( $p eq $peg ) {
	$alreadyin = 1;
	$error .= "CDS $peg is already in the subsystem<BR>\n";
      }
    }

    # if not put it in #
    if ( !$alreadyin ) {
      push @pegs, $peg;
    }

    # set pegs for cell #
    $subsystem->set_pegs_in_cell( $genome, $role, \@pegs );

    $comment .= "Added CDS $peg to the subsystem<BR>\n";
  }

  # write spreadsheet #
  $subsystem->db_sync();
  $subsystem->write_subsystem();

  return ( $comment, $error );

}

################################
# add genomes to the subsystem #
################################
sub add_genomes_to_subsystem {

  my ( $fig, $name, $addgenomes ) = @_;

  my $subsystem = new Subsystem( $name, $fig, 0 );
  my $comment = '';
  my $error = '';

  # go through checked genomes #
  foreach my $genomen ( @$addgenomes ) {
    $genomen =~ /^gacheckbox_(.*)\_(.*)/;
    my $genome = $1;
    my $variantcode = $2;
    $variantcode = "*".$variantcode;

    # add the genome to the subsystem #
    $subsystem->add_genome( $genome );
    $subsystem->set_variant_code( $subsystem->get_genome_index( $genome ), $variantcode );
    foreach my $role ( $subsystem->get_roles() ) {
      my @pegs = $fig->seqs_with_role( $role, "master", $genome);
      $subsystem->set_pegs_in_cell( $genome, $role, \@pegs);
    }
    $comment .= "Added Genome $genome to the Seed<BR>\n";
  }

  # write subsystem #
  $subsystem->db_sync();
  $subsystem->write_subsystem();

  return ( $comment );

}

###############################
# make the table for leftouts #
###############################
sub make_leftout_table {

  my ( $self, $fig, $cgi, $user, $can_alter, $name, $application, $datahash ) = @_;

  # table columns #
  my $table_columns = [ { name     => '' }, 
			{ name     => 'CDS',
			  sortable => 1 },
			{ name     => 'Function',
			  sortable => 1 },
			{ name     => 'Role',
			  sortable => 1 },
			{ name     => 'Genome',
			  sortable => 1 },
			{ name     => 'Other subsystems',
			  sortable => 1 } ];
  if ( !$can_alter ) {
    shift( @$table_columns );
  }

  my $table_data;
  my $somethingin = 0;

  # get mismatches from datahash #
  my @mismatches = @{ $datahash->{ 'leftouts' } };

  # go through mismatches #
  foreach my $p ( @mismatches ) {
    my $peg = $p->{ 'cds' };
    my $genome = $fig->genome_of( $p->{ 'cds' } );
    my $genomename = $fig->genus_species( $genome ) . "( $genome )";
    my $thisrole = $p->{ 'role' };
    $thisrole =~ s/ /\_/g;

    # get other subsystems it's in #
    my @subsystems = $fig->subsystems_for_peg( $p->{ 'cds' } );
    @subsystems = map { $_->[0] }
      grep { $_->[0] ne $name }
	@subsystems;

    # make string from it #
    my $sss = join( ', ', @subsystems );
    $sss = '-' if ( scalar( @subsystems ) < 1 );

    # make a checkbox #
    my $cb = $cgi->checkbox( -name     => 'adcheckbox',
			     -id       => "adcheckbox_$peg\_$thisrole",
			     -value    => "adcheckbox_$peg\_$thisrole",
			     -label    => '',
			     -checked  => 0,
			     -override => 1,
			   );

    my $thispeg = $p->{ 'cds' };
#    my $peg_link = &HTML::fid_link( $cgi, $thispeg, 0 );
    my $peg_link = $self->fid_link( $cgi, $thispeg, $user );
    $peg_link = "<A HREF='$peg_link' target=_blank>$thispeg</A>";

    # push row into the table data #
    if ( $can_alter ) {
      push @$table_data, [ $cb, $peg_link, $p->{ 'function' }, $p->{ 'role' }, $genomename, $sss ];
    }
    else {
      push @$table_data, [ $peg_link, $p->{ 'function' }, $p->{ 'role' }, $genomename, $sss ];
    }
    $somethingin = 1;
  }

  # create the table if content exists #
  if ( $somethingin ) {
    my $table = $self->application->component( 'adtable' );
    $table->columns( $table_columns );
    $table->data( $table_data );
    return 1;
  }
  return 0;
    
}

#################################
# make the table for mismatches #
#################################
sub make_mismatch_table {

  my ( $self, $fig, $cgi, $user, $can_alter, $name, $application, $datahash ) = @_;

  # table column headers #
  my $table_columns = [ { name     => '' }, 
			{ name     => 'CDS',
			  sortable => 1 },
			{ name     => 'Function',
			  sortable => 1 },
			{ name     => 'Role',
			  sortable => 1 },
			{ name     => 'Genome',
			  sortable => 1 },
			{ name     => 'Other subsystems',
			  sortable => 1 } ];

  if ( !$can_alter ) {
    shift @$table_columns;
  }

  my $table_data;
  my $somethingin = 0;

  # get mismatches from datahash #
  my @mismatches = @{ $datahash->{ 'mismatches' } };

  # go through them #
  foreach my $p ( @mismatches ) {
    my $peg = $p->{ 'cds' };
    my $role = $p->{ 'role' };
    my $genome = $fig->genome_of( $peg );
    my $genomename = $fig->genus_species( $genome ) . "( $genome )";

    # get other subsystems it's in #
    my @subsystems = $fig->subsystems_for_peg( $p->{ 'cds' } );
    @subsystems = map { $_->[0] }
      grep { $_->[0] ne $name }
	@subsystems;

    my $idname = 'mmcheckbox_'.$peg.'_to_'.$role;

    my $sss = join( ', ', @subsystems );
    $sss = '-' if ( scalar( @subsystems ) < 1 );

    # create checkbox #
    my $cb = $cgi->checkbox( -name     => 'mmcheckbox',
			     -id       => "$idname",
			     -value    => "$idname",
			     -label    => '',
			     -checked  => 0,
			     -override => 1,
			   );

#    my $peglink = &HTML::fid_link( $cgi, $peg, 0 );
    my $peglink = $self->fid_link( $cgi, $peg, $user );
    $peglink = "<A HREF='$peglink' target=_blank>$peg</A>";

    # put row into table data #
    if ( $can_alter ) {
      push @$table_data, [ $cb, $peglink, $p->{ 'function' }, $role, $genomename, $sss ];
    }
    else {
      push @$table_data, [ $peglink, $p->{ 'function' }, $role, $genomename, $sss ];
    }
      
    $somethingin = 1;
  }

  # create the table if content exists #
  if ( $somethingin ) {
    my $table = $application->component( 'mmtable' );
    $table->columns( $table_columns );
    $table->data( $table_data );
    return 1;
  }
  return 0;
    
}

#####################################
# make the table for genomes to add #
#####################################
sub make_maybeadd_table {

  my ( $fig, $cgi, $can_alter, $name, $application, $datahash ) = @_;

  # table column headers #
  my $table_columns = [ { name     => '' }, 
			{ name     => 'Taxid',
			  sortable => 1 },
			{ name     => 'Genome',
			  sortable => 1 },
			{ name     => 'Pattern',
			  sortable => 1 },
			{ name     => 'VariantCode',
			  sortable => 1 },
			{ name     => 'All Clustered',
			  sortable => 1 } ];
  if ( !$can_alter ) {
    shift( @$table_columns );
  }


  my $table_data;
  my $somethingin = 0;
  
  # get genomes that maybe should be added #
  my @maybeadds = @{ $datahash->{ 'maybeadd' } };

  # go through them #
  foreach my $p ( @maybeadds ) {
    my $genome = $p->{ 'tax' };
    my $genomename = $p->{ 'genome' };
    my $genomepattern = $p->{ 'pattern' };
    my $genomevc = $p->{ 'pvariant' };
    my $genomeclustered = $p->{ 'clustered' };
    
    my $cb = $cgi->checkbox( -name     => 'gacheckbox',
			     -id       => "gacheckbox_$genome\_$genomevc",
			     -value    => "gacheckbox_$genome\_$genomevc",
			     -label    => '',
			     -checked  => 0,
			     -override => 1,
			   );

    # push row into table data #
    if ( $can_alter ) {
      push @$table_data, [ $cb, $genome, $genomename, $genomepattern, $genomevc, $genomeclustered ];
    }
    else {
      push @$table_data, [ $genome, $genomename, $genomepattern, $genomevc, $genomeclustered ];
    }
    $somethingin = 1;
  }

  # create the table if content exists #
  if ( $somethingin ) {
    my $table = $application->component( 'gatable' );
    $table->columns( $table_columns );
    $table->data( $table_data );
    return 1;
  }
  return 0;
    
}

###################################
# get datahash from file warnings #
###################################
sub get_data {

  my ( $fig, $name ) = @_;

  my $datahash;
  my $mismatchesN = 0;
  my $leftoutN = 0;
  my @maybe_add = ();
  my @mismatches = ();
  my @leftouts = ();
  
  if (-e "$FIG_Config::data/Subsystems/$name/warnings") {

    $datahash->{ 'lastchecktime' } = localtime($^T - ((-M "$FIG_Config::data/Subsystems/$name/warnings") * 24 * 60 * 60));

    my @tmp = $fig->file_read( "$FIG_Config::data/Subsystems/$name/warnings" );

    foreach my $line ( @tmp ) {
      
      if ( $line =~ /mismatch\t([^\t]+)\t([^\t]+)\t([^\t]+)/ ) {
	
	my $peg = $1;
	my $functobe = $2;
	my $role = $3;
	my $func = $fig->function_of( $peg );
	$func =~ s/\s*\#.*$//;
	
	my @subs = $fig->peg_to_subsystems($peg);
	my $i;
	for ( $i = 0; ( $i < @subs ) && ( $name ne $subs[$i] ); $i++ ) {}
	#	  if ( $i < @subs ) {
	$mismatchesN++;
	push @mismatches, { 'cds'    => $peg,
			    'functobe' => $functobe,
			    'role'     => $role,
			    'function' => $func };
      }
      elsif ( $line =~ /left\-out\t([^\t]+)\t([^\t]+)\t/ ) {
	my $peg = $1;
	my $functobe = $2;
	my $func = $fig->function_of( $peg );

	if ( $func eq $functobe ) {

	  my @subs = $fig->peg_to_subsystems($peg);
	  my $i;
	  for ( $i=0; ( $i < @subs) && ( $name ne $subs[$i] ); $i++ ) {}
	  if ( $i == @subs ) {
	    $leftoutN++;
	    push @leftouts, { 'cds'    => $peg,
			      'functobe' => $functobe,
			      'role'     => $functobe,
			      'function' => $func };
	  }
	}
      }
      elsif ( $line =~ /maybe-add\t[^\t]+\t(\*?[^\t])+\t(\d+\.\d+)/ ) {
	push @maybe_add, { 'tax' => $2,
			   'genome'   => $fig->genus_species( $2 ),
			   'pvariant' => $1 };
      }
    }
  }
  $datahash->{ 'mismatchesN' } = $mismatchesN; 
  $datahash->{ 'leftoutN' } = $leftoutN; 
  $datahash->{ 'maybeaddN' } = scalar( @maybe_add );
  $datahash->{ 'mismatches' } = \@mismatches;
  $datahash->{ 'leftouts' } = \@leftouts;
  $datahash->{ 'maybeadd' } = \@maybe_add;

  return ( $datahash );
}

sub stripped_function_of {
    my($fig,$peg) = @_;

    my $func = $fig->function_of($peg);
    $func =~ s/\s*\#.*$//;
    return $func;
}

#############################################
# this function creates the on-the-fly data #
#############################################
sub checkdata_function {
  my ( $fig, $name ) = @_;
  my $datahash;

  # create a new subsystem object #
  my $subsystem = new Subsystem( $name, $fig, 0 );

  my $gsH = {};
  my ( @good, %good );

  my $curator = $subsystem->get_curator();
  my @roles   = $subsystem->get_roles();
  my @genomes = $subsystem->get_genomes();

  my @mismatches;
  my @leftouts;
  my @maybeadd = ();

  my $rdbH = $fig->db_handle;
  my $subsystemQ = quotemeta $name;
  my $query = "SELECT role,protein FROM subsystem_index WHERE subsystem='$subsystemQ'";
  my $relational_db_response = $rdbH->SQL($query);

#  # mismatches #
#  foreach $_ ( @$relational_db_response ) {
#    my ( $role, $peg ) = @$_;
#    my $func = &stripped_function_of($fig,$peg);
#    if ( ( index( $func, $role ) < 0) && ( $fig->is_real_feature( $peg ) ) ) {




  # mismatches #
  foreach $_ ( @$relational_db_response ) {
    my ( $role, $peg ) = @$_;
    if ( $fig->is_real_feature( $peg ) ) {
      my $func = &stripped_function_of($fig,$peg);
      my @roles_of_func = $fig->roles_of_function($func);
      my $roleI;
      for ( $roleI = 0; ( $roleI < @roles_of_func) && ( $roles_of_func[$roleI] ne $role ); $roleI++ ) {}

      if ( $roleI == @roles_of_func ) {
	
	push @mismatches, { 'cds'    => $peg,
			    'functobe' => $role,
			    'role'     => $role,
			    'function' => $func,
			    'genome'   => gs_of_peg( $fig, $peg, $gsH ),
			    'curator'  => $curator };
	
      }
      else {
	push( @good, $peg );
      }
    }
  }
  %good = map { $_ => 1 } @good;
  my $org_constraint = "(" . join(" or ",map { "(org = '$_')" } @genomes) . ")";
  my $role_constraint = "(" . join(" or ",map { my $roleQ = quotemeta $_; "(role = '$roleQ')" } @roles) . ")";
  $query = "SELECT prot,role  FROM roles WHERE $role_constraint AND $org_constraint";
  $relational_db_response = $rdbH->SQL($query);

  # leftouts #
  foreach $_ ( grep { ! $good{ $_->[0] } } @$relational_db_response ) {

    my ($peg,$role) = @$_;
    if ($fig->is_real_feature($peg)) {
      
      my $func = &stripped_function_of( $fig, $peg );
      push @leftouts, { 'cds'    => $peg,
			'functobe' => $role,
			'role'     => $role,
			'function' => $func,
			'genome'   => gs_of_peg( $fig, $peg, $gsH ),
			'curator'  => $curator };
    }
  }

  #############
  # maybeadds #
  #############

  my @non_aux_roles = grep { ! $subsystem->is_aux_role($_) } @roles;
  my %genomes;
  map { $genomes{ $_ } = 1 } @genomes;

  my $abbrevP;
  foreach my $role ( @roles ) {
    my $i = $subsystem->get_role_index( $role );
    my $abbrev = $role ? $subsystem->get_role_abbr( $i ) : "";
    $abbrevP->{ $role } = $abbrev;
  }

  my %variant_codes = map { $_ => $subsystem->get_variant_code( $subsystem->get_genome_index( $_ ) ) } @genomes;

  my( @has, $role, %has_filled );
  foreach my $genome ( @genomes ) {
    @has = ();
    foreach $role ( @roles ) {
      push( @has, ( $subsystem->get_pegs_from_cell( $genome, $role ) > 0 ) ? $abbrevP->{ $role } : () );
    }
    $has_filled{ join( ",", @has ) }->{ $variant_codes{ $genome } }++;
  }

  my $addGenome;
  my $roleQ;
  
  $role_constraint = "(" . join(" or ",map { $roleQ = quotemeta $_; "(role = '$roleQ')" } @non_aux_roles) . ")";
  $query = "SELECT prot,role  FROM roles WHERE $role_constraint";
  $relational_db_response = $rdbH->SQL($query);

  my %cand;

  foreach ( @$relational_db_response ) {
    my ( $peg,$role ) = @$_;
    my $genome = $fig->genome_of( $peg );

    unless ( defined( $genomes{ $genome } ) ) {
      $cand{ $genome }->{ $role } = $peg;
    }
  }

  # get variant codes for each genome here
  foreach my $g ( keys %cand ) {
    my @p = ();
    my @pegs_of_genome;
    foreach my $r ( @roles ) {
      if ( defined( $cand{ $g }->{ $r } ) ) {
	push @p, $abbrevP->{ $r };
      }
    }
    foreach my $r ( @non_aux_roles ) {
      if ( defined( $cand{ $g }->{ $r } ) ) {
	push @pegs_of_genome, $cand{ $g }->{ $r };
      }
    }
    my $patt = join( ',', @p );
    $addGenome->{ $g }->{ 'pattern' } = $patt;
    my $variantcode = getVarCodeFromPattern( $patt, \%has_filled );
    $addGenome->{ $g }->{ 'pvariant' } = $variantcode;

    $addGenome->{ $g }->{ 'clustered' } = 0;
    my @clusters = $fig->compute_clusters( \@pegs_of_genome, undef, 5000 );

    for ( my $i = 0; $i < scalar( @clusters ); $i++ ) {      
      my %countfunctions = map{ (scalar $fig->function_of( $_ ) => 1 ) } @{ $clusters[ $i ] };
      if ( scalar( keys %countfunctions ) == scalar( @non_aux_roles ) ) {
	$addGenome->{ $g }->{ 'clustered' } = 1;
      }
    }
  }

  foreach my $genome ( keys( %$addGenome ) ) {
    next if ( !$fig->is_complete( $genome ) );
    next if ( ( $addGenome->{ $genome }->{ 'pvariant' } eq '-1' ) ||
	      ( $addGenome->{ $genome }->{ 'pvariant' } eq '*-1' ) );

    push @maybeadd, 
      { 'tax'       => $genome,
	'genome'    => $fig->genus_species( $genome ),
	'curator'   => $curator, 
	'pvariant'  => $addGenome->{ $genome }->{ 'pvariant' },
	'pattern'   => $addGenome->{ $genome }->{ 'pattern' },
	'clustered' => $addGenome->{ $genome }->{ 'clustered' }
      };
  }

  @mismatches = grep { $_->{cds} =~ /\.peg\./ } @mismatches;
  @leftouts = grep { $_->{cds} =~ /\.peg\./ } @leftouts;

  $datahash->{ 'mismatchesN' } = scalar( @mismatches ); 
  $datahash->{ 'leftoutN' } = scalar( @leftouts ); 
  $datahash->{ 'maybeaddN' } = scalar( @maybeadd );
  $datahash->{ 'mismatches' } = \@mismatches;
  $datahash->{ 'leftouts' } = \@leftouts;
  $datahash->{ 'maybeadd' } = \@maybeadd;

  return ( $datahash );
  }


################################
# get genus and species of peg #
################################
sub gs_of_peg {
    my( $fig, $peg, $gsH ) = @_;

    my $gs;
    if ($peg =~ /^fig\|(\d+\.\d+)/)
    {
	my $genome = $1;
	$gs = $gsH->{$genome};
	if (! $gs) 
	{ 
	    $gsH->{$genome} = $gs = $fig->genus_species($genome);
	}
    }
    return $gs;
}


sub fid_link {
    my ( $self, $cgi, $fid, $user ) = @_;
    my $n;

    if ($fid =~ /^fig\|\d+\.\d+\.([a-zA-Z]+)\.(\d+)/) {
      if ( $1 eq "peg" ) {
	  $n = $2;
	}
      else {
	  $n = "$1.$2";
	}
    }

    my $link;


    my $dbmaster = $self->application->dbmaster;
    my $application = $self->application->backend; 

    my $seeduser = '';
    if ( defined( $user ) && ref( $user ) ) {
      my $preferences = $dbmaster->Preferences->get_objects( { user => $user,
							       name => 'SeedUser',
							       application => $application } );
      if ( defined( $preferences->[0] ) ) {
	$seeduser = $preferences->[0]->value();
      }
    }
#    $link = "./protein.cgi?prot=$fid&user=$seeduser\&new_framework=0";
    $link = qq~./seedviewer.cgi?page=Annotation&feature=$fid&user=$seeduser~;
    return $link;
}


sub getCheckButtons {
  my ( $element ) = @_;

  my $checkall    = "<INPUT TYPE=BUTTON name='CheckAll' value='Check All' onclick='checkAll( \"$element\" )'>\n";
  my $uncheckall  = "<INPUT TYPE=BUTTON name='UnCheckAll' value='Uncheck All' onclick='uncheckAll( \"$element\" )'>\n";
  
  return ( $checkall, $uncheckall );
}


sub getVarCodeFromPattern {
  my ( $patt, $has_filled ) = @_;

  my $score = 0;
  my $currvc = -1;
  my $pathash;


  if ( defined( $has_filled->{ $patt } ) ) {
    $pathash = $has_filled->{ $patt };
  }
  else {
    my $pscore = 0;
    my $actualpattern;

    foreach my $p ( keys %$has_filled ) {

      my %comppat = map { $_ => 1 } split( ',', $p );
      my %inpat = map { $_ => 1 } split( ',', $patt );
      my $defined = 1;
      my $wasin = 0;

      # look if my inpattern has all my roles from comppat
      foreach ( keys %comppat ) {
	$wasin = 1;
	if ( !defined( $inpat{ $_ } ) ) {
	  # missing one -> cannot be my pattern !
	  $defined = 0;
	  last;
	}
	else {
	  delete $inpat{ $_ };
	}
      }

      if ( $defined && $wasin ) {
	my $thisscore = 0;
	# now look what we're missing
	foreach ( keys %inpat ) {
	  $thisscore += 1;
	}
	if ( $thisscore > $pscore ) {
	  $pscore = $thisscore;
	  $actualpattern = $p;
	}
      }
    }
    if ( defined( $actualpattern ) ) {
      $pathash = $has_filled->{ $actualpattern };
    }
  }

  if ( !defined( $pathash ) ) {
    return -1;
  }

  foreach my $vc ( keys %$pathash ) {
    if ( $vc ne '0' ) {
      if ( $pathash->{ $vc } > $score ) {
	$currvc = $vc;
	$score = $pathash->{ $vc };
      }
    }
    else {
      $currvc = 0;
    }
  }
  return $currvc;
}
