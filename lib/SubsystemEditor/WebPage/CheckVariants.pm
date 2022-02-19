package SubsystemEditor::WebPage::CheckVariants;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;

use FIG;
use Boolean;

use base qw( WebPage );

1;

##################################################
# Method for registering components etc. for the #
# application                                    #
##################################################
sub init {
  my ( $self ) = @_;

  $self->application->register_component(  'Table', 'NewGenomesTable'  );
  $self->application->register_component(  'Table', 'FRTable'  );
  $self->application->register_component(  'Table', 'MismatchingTable'  );
  $self->application->register_component(  'Info', 'CommentInfo');
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
  
  my $fig = new FIG;
  my $cgi = $self->application->cgi;
  
  my $name = $cgi->param( 'subsystem' );
  my $ssname = $name;
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
    $fig->set_user( $seeduser );
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

  my $content = "<H1>Check Variants for Subsystem: $ssname</H1>";

  # put genomes into subsystem
  if ( $cgi->param( 'ADDGENOMES' ) ) {
    my @genomes = $cgi->param( 'undefcheckbox' );
    my ( $putcomment, $puterror ) = add_genomes_to_subsystem( $fig, $name, \@genomes );
    $comment .= $putcomment;
    $error .= $puterror;
  }
  # add variant codes for genomes
  if ( $cgi->param( 'CHANGEVARIANTS' ) ) {
    my @genomes = $cgi->param( 'mismcheckbox' );
    my ( $putcomment, $puterror ) = change_genome_variants( $fig, $name, \@genomes );
    $comment .= $putcomment;
    $error .= $puterror;
  }

  if ( !defined( $name ) ) {
    $content .= "<B>No subsystem given</B>";
    return $content;
  }

  my $subsystem = $fig->get_subsystem( $name );
  $self->{ 'subsystem' } = $subsystem;

  my ( $abbrev ) = format_roles( $self->application, $fig, $cgi, $subsystem );
  
  my $definitions  = $cgi->param( 'definitions' );
  my $rules        = $cgi->param( 'rules' );
  
  my ( @rulesI, @definitionsI );
  
  if ( defined( $definitions ) && $definitions =~ /\S/ ) {
    $definitions     =~ tr/\r/\n/;
    @definitionsI  = grep { $_ } split( /\n/, $definitions );
  }
  
  if ( defined( $rules ) && $rules =~ /\S/ ) {
    $rules    =~ tr/\r/\n/;
    @rulesI  = grep { $_ } split( /\n/, $rules );
  }
  
  if ( @rulesI < 1 ) {
    
    my $saved_definitions = $self->{ 'subsystem' }->get_checkvariant_definitions();
    my $saved_rules = $self->{ 'subsystem' }->get_checkvariant_rules();

    $content .= $self->start_form( 'checkvariants', { subsystem => $name } );
    $content .= $cgi->submit( 'Compute Predicted Variant Codes' );
    $content .= $cgi->h2('Roles');
    $content .= "<P>These are the roles of the subsystem $ssname. The abbreviations can be used in the definitions and rules you provide below.</P>";
    $content .= $self->application->component( 'FRTable' )->output();
    $content .= $cgi->h2('Definitions');
    $content .= "<P>Definitions are variables that are defined to be used in the rules. They are non-mandatory, and are stated as <I>VARIABLE means DEFINITION</I>.<BR>They use the logic operators <I>and</I>, <I>or</I> and <I>not</I>. They are given as a 2-column table (everything before the first space character is the first,<BR>everything after that the second column), and might look like this for Histidine Degradation:</P>";
    $content .= '<P>*NfoD means NfoD or NfoD2<BR>';
    $content .= '*Alt3 means *NfoD and ForI<BR>';
    $content .= '*Req means HutH and HutU and HutI</P>';
    $content .= $cgi->textarea( -name => 'definitions', -rows => 10, columns => 100, value => $saved_definitions );

    $content .= $cgi->h2('Rules');
    $content .= "<P>A rule describes for a variant code, what functions must be present. It is stated as <I>VARIANT means RULE</I>. A rule can use role abbreviations<BR>and definitions given above. They can be connected by logic operators <I>and</I>, <I>or</I> and <I>not</I>, as well as the expression <I># of {...}</I>, which can also<BR>be nested. For Histidine Degradation, rules might look like this:</P>";
    $content .= '<P>1.111 means *Req and GluF and HutG and *Alt3<BR>';
    $content .= '1.101 means *Req and GluF and *Alt3<BR>';
    $content .= '1.011 means *Req and HutG and *Alt3<BR>';
    $content .= '1.001 means *Req and *Alt3<BR>';
    $content .= '1.010 means *Req and HutG<BR>';
    $content .= '1.100 means *Req and GluF<BR>';
    $content .= '0 means 2 of {HutH,HutU,HutI,1 of {GluF,HutG,*Alt3}}</P>';
    $content .= $cgi->textarea( -name => 'rules', -rows => 10, columns => 100, value => $saved_rules );
    $content .= "<p>";
    $content .= "Compute for specified genome: ";
    $content .= $cgi->textfield(-name => "specified_genome", -size => 15);
    $content .= "<br>\n";
    $content .= $cgi->checkbox(-name => "debug_prediction",  -label => 'Show prediction debugging');
    $content .= "<p>\n";
    $content .= $cgi->submit( 'Compute Predicted Variant Codes' );
    $content .= $cgi->end_form;
  }
  else {
    my $col_headers_undef = [ '', "Predicted Variant", "Genome", "Genus/Species" ];
    my $tab_undef = [];
    my $col_headers_mismatch = [ '', "Actual Variant", "Predicted Variant", "Genome", "Genus/Species"];
    my $tab_mismatch = [];

    my %genomesS = map { $_ => 1 } $subsystem->get_genomes;

#########
    my $encoding = [[],0];   # Encoding is a 2-tuple [Memory,NxtAvail]
    my $abbrev_to_loc = {};

    my $rolesarr  = &load_roles($cgi,$encoding,$abbrev_to_loc,$abbrev);
    my @roles = @$rolesarr;
    if (@roles < 1) {
      $error .= "Roles are invalid<BR>";
    }
    else {
      my $succ = $self->save_definitions_to_file( \@definitionsI );
      my ( $puterror, $rc ) = &load_definitions($cgi,$encoding,$abbrev_to_loc,$definitions);
      $error .= $puterror;
      if ( ! $rc || $puterror ne '' ) {
	$error .= $cgi->h2( "Definitions are invalid" );
      }
      else {
	$self->save_rules_to_file( \@rulesI );
	my ( $puterror2, $rulesarr ) = &Boolean::parse_rules($encoding,$abbrev_to_loc,\@rulesI);
	$error .= $puterror2;
	
	my @rules = @$rulesarr;
	if ( @rules < 1 || $puterror2 ne '' ) {
	  $error .= $cgi->h2( "There are invalid rules, please go back and fix this!" );
	}
	else {
	  my $n = @rules;
	  $comment .= $cgi->h2("successfully parsed $n rules");
	  my $roles_present = {};
	  my $role_to_pegs  = {};
	  foreach my $role ( @roles ) {
	    $role_to_pegs->{$role} = [ sort { &FIG::by_fig_id($a,$b) } 
				       $fig->prots_for_role($role)
				     ];
	  }
	  my $compiled = [$encoding,$abbrev_to_loc,\@rules];

	  my @genomes;
	  if ($cgi->param('specified_genome'))
	  {
	      @genomes = ($cgi->param('specified_genome'));
	  }
	  else
	  {
	      @genomes = $fig->genomes('complete');
	  }
	  
	  my $debug_output;

	  my $operational = 0;
	  foreach my $genome ( map { $_->[0] } 
			       sort { $a->[1] cmp $b->[1] } 
			       map { [ $_, $fig->genus_species( $_ ) ] } 
			       @genomes )  {

	      my $relevant_genes = {};
	      foreach my $role ( sort keys( %$role_to_pegs ) ) 
	      {
		  $relevant_genes->{ $role } = [ sort { &FIG::by_fig_id( $a, $b ) }
				   grep { &FIG::genome_of( $_ ) eq $genome }
				   @{ $role_to_pegs->{ $role } } ];
	      }
	      my @roles_present = grep { my $hits = $relevant_genes->{$_}; (@$hits > 0) } keys(%$relevant_genes);
	      my ($vcT,$debug) = &Boolean::find_vc( $compiled, \@roles_present);

	      $debug_output .= $debug if ($cgi->param('debug_prediction') && $cgi->param('specified_genome'));

	      if ( ($vcT ne '0') && ($vcT ne '-1' )) { $operational++ }
	      
	      if (($vcT ne '-1') && ( ! $genomesS{ $genome } ) ) 
	      {
		  my $cb = $cgi->checkbox( -name     => 'undefcheckbox',
					   -id       => "undefcheckbox_$genome\_$vcT",
					   -value    => "undefcheckbox_$genome\_$vcT",
					   -label    => '',
					   -checked  => 0,
					   -override => 1,
					   );
	      
		  push( @$tab_undef, [ $cb, $vcT, $genome, $fig->genus_species( $genome ) ] );
	      }
	      else {		   
		  my $vcS = $subsystem->get_variant_code_for_genome($genome);
		  $vcS = '' unless defined($vcS);
		  if ((( $vcT ne $vcS ) && (!($vcS eq '' && $vcT eq '-1'))))
		  {
		      # make a checkbox #
		      my $cb = $cgi->checkbox( -name     => 'mismcheckbox',
					       -id       => "mismcheckbox_$genome\_$vcT",
					       -value    => "mismcheckbox_$genome\_$vcT",
					       -label    => '',
					       -checked  => 0,
					       -override => 1,
					       );
		      push( @$tab_mismatch,[ $cb, $vcS, $vcT, $genome, $fig->genus_species( $genome ) ] );
		  }
	      }
	  }
	  $comment .= $cgi->h2("Got $operational operational variants.");
	  
	  if ( defined( $comment ) && $comment ne '' ) {
	    my $info_component = $self->application->component( 'CommentInfo' );
	    
	    $info_component->content( $comment );
	    $info_component->default( 0 );
	    $content .= $info_component->output();
	  }    
	  
	  $content .= $self->start_form( 'checkvariants', { subsystem   => $name,
							    definitions => $cgi->param( 'definitions' ),
							    rules       => $cgi->param( 'rules' ) } );
	  
	  if ( @$tab_undef > 0 ) {	     
	    my $undeftable = $self->application->component( 'NewGenomesTable' );
	    $undeftable->columns( $col_headers_undef );
	    $undeftable->data( $tab_undef );
	    
	    $content .= "<H2>Rules</H2>";
	    $rules =~ s/\n\n/\n/g;
	    $rules =~ s/\n/<BR>/g;
	    $definitions =~ s/\n\n/\n/g;
	    $definitions =~ s/\n/<BR>/g;
	    $content .= $rules;
	    $content .= "<H2>Definitions</H2>";
	    $content .= $definitions;
	    
	    $content .= "<H2>".scalar( @$tab_undef )." Genomes to Be Added To Subsystem</H2>";
	    $content .= $undeftable->output();
	    $content .= $cgi->br;
	    my $checkall2    = "<INPUT TYPE=BUTTON name='CheckAll' value='Check All' onclick='checkAll( \"undefcheckbox\" )'>\n";
	    my $uncheckall2  = "<INPUT TYPE=BUTTON name='UnCheckAll' value='Uncheck All' onclick='uncheckAll( \"undefcheckbox\" )'>\n";
	    $content .= "<TABLE><TR><TD>$checkall2</TD><TD>$uncheckall2</TD></TR>";
	    $content .= "<TR><TD COLSPAN=2><INPUT TYPE=SUBMIT VALUE='Add selected Genomes to my subsystem' ID='ADDGENOMES' NAME='ADDGENOMES'></TD></TR></TABLE>";
	    $content .= $cgi->br;
	  }
	  
	  if ( @$tab_mismatch > 0 ) {
	    my $mismatchtable = $self->application->component( 'MismatchingTable' );
	    $mismatchtable->columns( $col_headers_mismatch );
	    $mismatchtable->data( $tab_mismatch );
	    
	    $content .= "<H2>".scalar( @$tab_mismatch )." Genomes With Mismatching Variant Codes</H2>";
	    $content .= $mismatchtable->output();
	    $content .= $cgi->br;

	    my $checkall    = "<INPUT TYPE=BUTTON name='CheckAll' value='Check All' onclick='checkAll( \"mismcheckbox\" )'>\n";
	    my $uncheckall  = "<INPUT TYPE=BUTTON name='UnCheckAll' value='Uncheck All' onclick='uncheckAll( \"mismcheckbox\" )'>\n";
	    $content .= "<TABLE><TR><TD>$checkall</TD><TD>$uncheckall</TD></TR>";
	    $content .= "<TR><TD COLSPAN=2><INPUT TYPE=SUBMIT VALUE='Change Selected Variants to Predicted Variants' ID='CHANGEVARIANTS' NAME='CHANGEVARIANTS'></TD></TR></TABLE>";
	    $content .= $cgi->br;
	    $content .= $self->end_form( 'checkvariants', { subsystem => $name } );
	  }
	  if ($debug_output)
	  {
	      $content .= "<pre>\n$debug_output\n</pre>\n";
	  }
	}
      }
    }
  }
  ##################
  # Display errors #
  ##################
  
  if ( defined( $error ) && $error ne '' ) {
    $self->application->add_message( 'warning', $error );
  }

  return $content;
}



sub load_roles {
    my($cgi,$encoding,$abbrev_to_loc,$abbrs) = @_;

    my $comment = '';
    my @roles = ();
    foreach my $role ( keys %$abbrs ) {
      my $loc = &add_to_encoding($encoding,['role',$role]);
      $abbrev_to_loc->{ $abbrs->{ $role } } = $loc;
      push(@roles,$role);
    }
    return \@roles;
}

sub add_to_encoding {
    my($encoding,$val) = @_;

    my($mem,$nxt) = @$encoding;
    $mem->[$nxt] = $val;
    $encoding->[1]++;
    return $nxt;
}

sub load_definitions {
  my ( $cgi, $encoding, $abbrev_to_loc, $defI ) = @_;
  
  my $error = '';
  my ( $puterror, $rc ) = &Boolean::parse_definitions($encoding,$abbrev_to_loc,$defI);
  $error .= $puterror;
  if ( ! $rc || $puterror ne '' ) 
  {
      $error .= "<br>Definitions are invalid";
  }
  return ( $error, $rc );
}

sub is_rule_true {
    my( $rule, $relevant_genes ) = @_;

    my ( $variant,$exp ) = @$rule;
    return &is_true_exp( $exp, $relevant_genes ) ? $variant : undef;
}

sub is_true_exp {
    my($bool,$relevant_genes) = @_;

    my($nodes,$root) = @$bool;
    my $val = $nodes->[$root];
    if (! ref  $val) 
    { 
	return &is_true_exp([$nodes,$val],$relevant_genes);
    }
    else
    {
	my $op = $val->[0];

	if ($op eq 'role')
	{
	    my $x;
	    return (($x = $relevant_genes->{$val->[1]}) && (@$x > 0)) ? 1 : 0;
	}
	elsif ($op eq "of")
	{
	    my $truth_value;
	    my $count = 0;
	    foreach $truth_value (map { &is_true_exp([$nodes,$_],$relevant_genes) } @{$val->[2]})
	    {
		if ($truth_value) { $count++ }
	    }
	    return $val->[1] <= $count;
	}
	elsif ($op eq "not")
	{
	    return &is_true_exp([$nodes,$val->[1]],$relevant_genes) ? 0 : 1;
	}
	else
	{
	    my $v1 = &is_true_exp([$nodes,$val->[1]],$relevant_genes);
	    my $v2 = &is_true_exp([$nodes,$val->[2]],$relevant_genes);
	    if ($op eq "and") { return $v1 && $v2 };
	    if ($op eq "or")  { return $v1 || $v2 };
	    if ($op eq "->")  { return ((not $v1) || $v2) }
	    else 
	    {
		print STDERR &Dumper($val);
		die "invalid expression";
	    }
	}
    }
}

sub print_bool {
    my($bool) = @_;

    my $s = &printable_bool($bool);
    print $s,"\n";
}

sub printable_bool {
    my($bool) = @_;

    my($nodes,$root) = @$bool;
    my $val = $nodes->[$root];

    if (! ref  $val) 
    { 
	return &printable_bool([$nodes,$val]);
    }
    else
    {
	my $op = $val->[0];

	if ($op eq 'role')
	{
	    return $val->[1];
	}
	elsif ($op eq "of")
	{
	    my @expanded_args = map { &printable_bool([$nodes,$_]) } @{$val->[2]};
	    my $args = join(',',@expanded_args);
	    return "$val->[1] of {$args}";
	}
	elsif ($op eq "not")
	{
	    return "($op " .  &printable_bool([$nodes,$val->[1]]) . ")";
	}
	else
	{
	    return "(" . &printable_bool([$nodes,$val->[1]]) . " $op " . &printable_bool([$nodes,$val->[2]]) . ")";
	}
    }
}


###############################
# get a functional role table #
###############################
sub format_roles {
    my( $application, $fig, $cgi, $subsystem ) = @_;
    my( $i );

    my $col_hdrs = [ "Column", "Abbrev", "Functional Role" ];

    my ( $tab, $abbrevP ) = format_existing_roles( $fig, $subsystem );

    # create table from parsed data
    my $table = $application->component( 'FRTable' );
    $table->columns( $col_hdrs );
    $table->data( $tab );

    return ( $abbrevP );
}

#########################################
# get rows of the functional role table #
#########################################
sub format_existing_roles {
    my ( $fig, $subsystem ) = @_;
    my $tab = [];
    my $abbrevP = {};
    my $n = 1;

    foreach my $role ( $subsystem->get_roles ) {
      my $i = $subsystem->get_role_index( $role );
      my $abbrev = $role ? $subsystem->get_role_abbr( $i ) : "";
      $abbrevP->{ $role } = $abbrev;
      push( @$tab, [ $n, $abbrev, $role ] );
      $n++;
    }

    return ( $tab, $abbrevP );
}



################################
# add genomes to the subsystem #
################################
sub change_genome_variants {

  my ( $fig, $name, $addgenomes ) = @_;

  my $subsystem = new Subsystem( $name, $fig, 0 );
  my $comment = '';
  my $error = '';

  # go through checked genomes #
  foreach my $genomen ( @$addgenomes ) {
    $genomen =~ /^mismcheckbox_(.*)\_(.*)/;
    my $genome = $1;
    my $variantcode = $2;

    # add the genome to the subsystem #
    $subsystem->set_variant_code( $subsystem->get_genome_index( $genome ), $variantcode );
    $comment .= "Set Variant Code of $genome to $variantcode<BR>\n";
  }

  # write subsystem #
  $subsystem->db_sync();
  $subsystem->write_subsystem();

  return ( $comment );

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
    $genomen =~ /^undefcheckbox_(.*)\_(.*)/;
    my $genome = $1;
    my $variantcode = $2;
#    $variantcode = "*".$variantcode;

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

sub save_definitions_to_file {
  my ( $self, $definitions ) = @_;

  my $string = '';
  foreach my $s ( @$definitions ) {
    chomp $s;
    $string .= $s;
    $string .= "\n";
  }
  $self->{ 'subsystem' }->save_checkvariant_definitions( $string );
}

sub save_rules_to_file {
  my ( $self, $rules ) = @_;

  my $string = '';
  foreach my $s ( @$rules ) {
    chomp $s;
    $string .= $s;
    $string .= "\n";
  }
  $self->{ 'subsystem' }->save_checkvariant_rules( $string );

}
