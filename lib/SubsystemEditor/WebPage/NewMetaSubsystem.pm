package SubsystemEditor::WebPage::NewMetaSubsystem;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;

use MetaSubsystem;

use FIG;

use base qw( WebPage );

1;

##############################################################
# Method for registering components etc. for the application #
##############################################################
sub init {
  my ( $self ) = @_;

  $self->application->register_component( 'Table', 'sstable'  );
  $self->application->register_component( 'TabView', 'SelectionTabView' );
  $self->application->register_component( 'OrganismSelect', 'OSelect');
  $self->application->register_component( 'Info', 'CommentInfo');
  $self->application->register_component( 'Hover', 'TestHover' );
  $self->application->register_component( 'FilterSelect', 'SubsystemSelect' );
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
  }

  if ( $user ) {
    $can_alter = 1;
    $fig->set_user( $seeduser );
  }


  my $hiddenvalues = {};
  my $hiddensubsystems = '';

  my @chosen_subsystems;
  if ( defined( $cgi->param( 'buttonpressed' ) ) && $cgi->param( 'buttonpressed' ) eq 'Select' ) {
    @chosen_subsystems = $cgi->param( 'the_subsystems' );
    foreach my $ss ( @chosen_subsystems ) {
      $hiddensubsystems .= "<INPUT TYPE=HIDDEN NAME='known_subsystems' VALUE='$ss'>";
    }
  }
  else {
    @chosen_subsystems = $cgi->param( 'known_subsystems' );
    foreach my $ss ( @chosen_subsystems ) {
      $hiddensubsystems .= "<INPUT TYPE=HIDDEN NAME='known_subsystems' VALUE='$ss'>";
    }
  }
  my $ready_link = '';
  my $build_subsets_string = $cgi->param( 'build_subsets_string' );


  ##############################
  # Construct the page content #
  ##############################
 
  my $content = "<H2>Create New Meta Subsystem</H2>";

  if ( !$user ) {
    $content .= "No user given. Please log in before you create a Metasubsystem.";
    return $content;
  }

  my ( $error, $comment ) = ( "", "" );

  #########
  # TASKS #
  #########

  if ( defined( $cgi->param( 'buttonpressed' ) ) && $cgi->param( 'buttonpressed' ) eq 'Build' ) {
    my $whichgenomes = $cgi->param( 'the_genomes' );

    my $msname = $cgi->param( 'SSNAME' );
    if ( defined( $msname ) && $msname ne '' ) {
      $ready_link = $self->create_meta_subsystem( $fig, $cgi, $msname, \@chosen_subsystems, $whichgenomes, $build_subsets_string );
    }
    else {
      $error .= "You have not specified a name for your new metasubsystem. Please specify a name and I can create it<BR\n";
    }
  }
  if ( defined( $cgi->param( 'buttonpressed' ) ) && $cgi->param( 'buttonpressed' ) =~ /^DeleteSubset/ ) {
    my $deletewhich = $cgi->param( 'buttonpressed' );
    $deletewhich =~ /DeleteSubset\_(.*)/;
    my $subset_to_delete = $1;

    my @bsss = split( "\n", $build_subsets_string );
    $build_subsets_string = '';
    my $sstodeltemp = $subset_to_delete . "##-##";
    foreach ( @bsss ) {
      unless ( $_ =~ /^$sstodeltemp/ ) {
	$build_subsets_string .= $_."\n";
      }
    }
  }
  if ( defined( $cgi->param( 'buttonpressed' ) ) && $cgi->param( 'buttonpressed' ) eq 'CreateSubset' ) {
    my $newSubsetName = $cgi->param( 'subsetname' );
    
    if ( !defined( $newSubsetName ) || $newSubsetName eq '' ) {
      $error .= "No Subset Name given for your new Subset, please specify a unique name<BR>";
    }
    else {
      my @whichs = $cgi->param( "rolesCreateSubset" );
      
      foreach my $ws ( @whichs ) {
	
	$build_subsets_string .= $newSubsetName;
	$ws =~ /role(##-##.*)/;
	my $this = $1;
	$this =~ s/\r//g;
	$build_subsets_string .= $this;
	$build_subsets_string .= "\n";
      }
    }
  }

  ############################
  # Build HTML Elements here #
  ############################

  my $choose_subsystems = $self->choose_subsystems( $fig, $cgi );
  my $choose_genomes = $self->choose_genomes( $fig, $cgi, \@chosen_subsystems );
  my $choose_subsets = $self->choose_subsets( $fig, $cgi, \@chosen_subsystems, $build_subsets_string );
  my $metasslink = $self->ready_link( $fig, $cgi, $ready_link );

  my $selecttabview = $self->application->component( 'SelectionTabView' );
  $selecttabview->width( 900 );
  $selecttabview->add_tab( '<H2>&nbsp; Choose Subsystems &nbsp;</H2>', "$choose_subsystems" );
  $selecttabview->add_tab( '<H2>&nbsp; Choose Subsets &nbsp;</H2>', "$choose_subsets" );
  $selecttabview->add_tab( '<H2>&nbsp; Choose Genomes &nbsp;</H2>', "$choose_genomes" );
  $selecttabview->add_tab( '<H2>&nbsp; Process &nbsp;</H2>', "$ready_link" );

  if ( defined( $cgi->param( 'defaulttabhidden' ) ) ) {
    $selecttabview->default( $cgi->param( 'defaulttabhidden' ) );
  }
  else {
    $selecttabview->default( 0 );
  }


  my $subsetstable = $self->application->component( 'sstable' );

  my $subsetstablecols = [];
  my $bss = $build_subsets_string || '';

  my @sstablelines = split( "\n", $bss );
  my %sstablehash;
  foreach my $sstline ( @sstablelines ) {
    my @ta = split( '##-##', $sstline );
    push @{ $sstablehash{ $ta[0] } }, { data => $ta[2], tooltip => $ta[1] };
  }
  
  foreach my $key ( keys %sstablehash ) {
    my $button_subset = "<INPUT TYPE=BUTTON VALUE='Delete' ONCLICK='SubmitNewMeta( \"DeleteSubset_$key\", 1 );'>";
    my $stuff = $sstablehash{ $key };
    my @sdata;
    my @stooltip;
    foreach my $s ( @$stuff ) {
      push @sdata, $s->{ 'data' };
      push @stooltip, $s->{ 'tooltip' };
    }

    my $frs = join( ', ', @sdata );
    my $tts = join( "<BR>", @stooltip );
    my $tat = [ $key, { data => $frs, tooltip => $tts }, $button_subset ];
    push @$subsetstablecols, $tat;
  }
  
  $subsetstable->columns( [ 'Name', 'FRs', '' ] );
  $subsetstable->data( $subsetstablecols );

  ################
  # HIDDENVALUES #
  ################

  # add hidden parameter for the tab that is actually open #
  my $dth = 0;

  if ( defined( $cgi->param( 'defaulttabhidden' ) ) ) {
    $dth = $cgi->param( 'defaulttabhidden' );
  }

  $hiddenvalues->{ 'buttonpressed' } = 'none';
  $hiddenvalues->{ 'defaulttabhidden' } = $dth;
  $hiddenvalues->{ 'build_subsets_string' } = $build_subsets_string;

  #################
  # Build Content #
  #################

  if ( defined( $comment ) && $comment ne '' ) {
    my $info_component = $self->application->component( 'CommentInfo' );

    $info_component->content( $comment );
    $info_component->default( 0 );
    $content .= $info_component->output();
  }    

  $content .= $self->start_form( 'form', $hiddenvalues );

  $content .= $hiddensubsystems;

  my $msname = $cgi->param( 'SSNAME' );
  if ( !defined( $msname ) ) {
    $msname = '';
  }

  my $infotable = "<TABLE><TR><TH>Name:</TH><TD><INPUT TYPE=TEXT NAME='SSNAME' ID='SSNAME' VALUE='$msname' STYLE='width: 772px;'></TD><TR>";
  if ( $user ) {
    $infotable .= "<TR><TH>Author:</TH><TD>".$seeduser."</TD></TR>";
  }
  else {
    $infotable .= "<TR><TH>Author:</TH><TD></TD></TR>";
  }

  if ( $can_alter ) {
    $infotable .= "<INPUT TYPE=SUBMIT VALUE='Save Changes' ID='SUBMIT' NAME='SUBMIT'>";
  }

  $infotable .= "<TR><TH>Defined Subsystems:</TH><TD>".join( ',<BR>', @chosen_subsystems )."</TD></TR>";
  $infotable .= "<TR><TH>Defined Subsets:</TH><TD>".$subsetstable->output()."</TD></TR>";

  $infotable .= "</TR></TABLE";

  $content .= $infotable;

  $content .= "<BR><BR>\n";

  $content .= $selecttabview->output();

  my $hover_component = $self->application->component( 'TestHover' );
  $content .= $hover_component->output();

  $content .= $self->end_form();


  ###############################
  # Display errors and comments #
  ###############################
 
  if ( defined( $error ) && $error ne '' ) {
    $self->application->add_message( 'warning', $error );
  }

  return $content;
}


sub choose_subsystems {
  
  my ( $self, $fig, $cgi ) = @_;

  my $panel = '<BR>';

  my @subsystems = sort $fig->all_subsystems();

#  # now special sets #
#  $panel .= $cgi->scrolling_list( -id       => 'the_subsystems', 
#				  -name     => 'the_subsystems',
#				  -values   => \@subsystems,
#				  -default  => 'None',
#				  -size     => 10,
#				  -multiple => 1
#				);

  my $subsystem_select_component = $self->application->component( 'SubsystemSelect' );
  my @subsystem_names = sort( $fig->all_subsystems() );
  my @subsystem_labels = @subsystem_names;
  map { $_ =~ s/_/ /g } @subsystem_labels;
  $subsystem_select_component->values( \@subsystem_names );
  $subsystem_select_component->labels( \@subsystem_labels );
  $subsystem_select_component->name( 'the_subsystems' );
  $subsystem_select_component->multiple( 1 );
  $subsystem_select_component->width(600);

  $panel .= $subsystem_select_component->output();  
  $panel .= "<BR><INPUT TYPE=BUTTON VALUE='Select' ONCLICK='SubmitNewMeta( \"Select\", 1 );'>";

  return $panel;
}

sub choose_genomes {

  my ( $self, $fig, $cgi, $subsystems ) = @_;

  my $panel = '<BR>';

#  foreach my $ss ( @$subsystems ) {
#    $panel .= $ss."<BR>";
#  }

  $panel .= "<TABLE>";

  $panel .= "<TR><TD><INPUT TYPE='RADIO' name='the_genomes' value='all_in_one'>All genomes present in at least one subsystem</TD></TR>";
  $panel .= "<TR><TD><INPUT TYPE='RADIO' name='the_genomes' value='all_in_all'>All genomes present in all chosen subsystems</TD></TR>";
  $panel .= "<TR><TD><INPUT TYPE='RADIO' name='the_genomes' value='all_in_seed'>All genomes present in the SEED</TD></TR>";
  $panel .= "<TR><TD><INPUT TYPE='RADIO' name='the_genomes' value='all_in_field'>Genomes selected here:</TD></TR>";

  #################################
  # Put The New OrganismSelect in #
  #################################
  my $oselect = $self->application->component( 'OSelect' );
  $oselect->multiple( 1 );
  $oselect->width( 500 );
  $oselect->name( 'sel_genome' );

  $panel .= "<TR><TD>".$oselect->output()."</TD></TR>";

  $panel .= "</TABLE>";
  $panel .= "<BR><INPUT TYPE=BUTTON VALUE='Build' ONCLICK='SubmitNewMeta( \"Build\", 3 );'>";

  return $panel;

}

sub choose_subsets {

  my ( $self, $fig, $cgi, $subsystems ) = @_;

  my $panel = '<H3>Subset Name</H3>';
  $panel .= "<P>Subset names work the same way as in a normal subsystem, using a * in front of the name if the subset [...]</P>";

  my $textfield = "<INPUT TYPE=TEXT NAME=\"subsetname\" SIZE=10>";
  my $textbutton = "<INPUT TYPE=BUTTON VALUE='Create Subset' ONCLICK='SubmitNewMeta( \"CreateSubset\", 1 );'>";
  my $donesubsets = "<INPUT TYPE=BUTTON VALUE='Done Creating Subsets' ONCLICK='SubmitNewMeta( \"Genomes\", 2 );'>";
  $panel .= "<TABLE><TD><B>Subset Name:</B></TD><TD>$textfield</TD></TABLE>";
  $panel .= "<H3>Choose members of the subset</H3>";
  $panel .= "<P>Members of the subset can be from different subsystems. Check the functional roles that should be the members of the subsystem and press \'Create Subset\' to finish.</P>";

  my @createtables;
  
  foreach my $ssname ( @$subsystems ) {
    my $ssname_nice = $ssname;
    $ssname_nice =~ s/\_/ /g;
    
    my $sshandle = new Subsystem( $ssname, $fig, 0 );
    my @roles = $sshandle->get_roles();

    my $checkall = "<INPUT TYPE=BUTTON name='CheckAll' value='Check All' onclick='checkAll( \"rolesCreateSubset\", \"$ssname\" )'>\n";
    my $uncheckall  = "<INPUT TYPE=BUTTON name='UnCheckAll' value='Uncheck All' onclick='uncheckAll( \"rolesCreateSubset\", \"$ssname\" )'>\n";

    # construct subsets create table #
    my $createtable = "<B>$ssname_nice</B> - $checkall $uncheckall<BR>";
    $createtable .= "<TABLE>";
    my $checkline = '';
    my $thline = '';
    my $combline = '';
    my $hover_component = $self->application->component( 'TestHover' );

    my $counter = 0;
    foreach my $r ( @roles ) {
      $counter++;
      my $abb = $sshandle->get_abbr_for_role( $r );
      my $thisname = $abb."##-##".$ssname;
      $hover_component->add_tooltip( $thisname, $r );
      $thline .= "<TH onmouseover='hover(event, \"$thisname\", " . $hover_component->id . ");'>$abb</TH>";
      
      my $role_checkbox = $cgi->checkbox( -name     => "rolesCreateSubset",
					  -id       => "role##-##$ssname##-##$abb",
					  -value    => "role##-##$ssname##-##$abb",
					  -label    => '',
					  -checked  => 0,
					  -override => 1,
					);

      $checkline .= "<TD>$role_checkbox</TD>";
      if ( $counter == 10 ) {
	$counter = 0;
	$combline .= $thline . "</TR>\n<TR>". $checkline . "</TR>\n<TR>";
	$thline = '';
	$checkline = '';
      }
    }
    if ( $counter != 0 ) {
      $combline .= $thline . "</TR>\n<TR>". $checkline . "</TR>\n<TR>";
    }

    $createtable .= $combline;
    $createtable .= "</TR>";
    $createtable .= "</TABLE>";

    push @createtables, $createtable;
  }

  $panel .= "<TABLE>";
  foreach my $ct ( @createtables ) {
    $panel .= "<TR><TD>$ct</TD></TR>";
  }

  $panel .= "<TR><TD>$textbutton</TD><TD>$donesubsets</TD></TR>";
  $panel .= "</TABLE>";
  return $panel;

}

sub ready_link {
  my ( $self, $fig, $cgi, $link ) = @_;

  my $panel = '<BR>';
  $panel .= "Your meta subsystem was build. Klick here to view it";

  return $panel;
}

sub create_meta_subsystem {
  my ( $self, $fig, $cgi, $msname, $chosen_subsystems, $whichgenomes, $bss ) = @_;
  my $link;

  $bss =~ s/\r//g;
  $bss =~ s/##-##/\t/g;

  my $msgenomes = get_ms_genomes( $fig, $cgi, $chosen_subsystems, $whichgenomes );
  my %hashgenomes = map { $_ => 1 } @$msgenomes;
  my $mssubsets = get_ms_subsets( $bss );
  my %hashsubsystems = map { $_ => 1 } @$chosen_subsystems;
  my $view;
  
  foreach my $subset ( keys %$mssubsets ) {
    $view->{ 'Subsets' }->{ $subset } = { 'visible' => 1,
					  'collapsed' => 1 };
  }

  my $metass = new MetaSubsystem( $msname, $fig, 1, \%hashsubsystems, \%hashgenomes, $mssubsets, $view );

  if ( ref( $metass ) ) {
    my $metasubsysurl = "SubsysEditor.cgi?page=MetaSpreadsheet&metasubsystem=$msname";
    $link .= "<H3> Creating Metasubsystem $msname was successfull.<BR>";
    $link .= "<H3> Click <A HREF='$metasubsysurl' target = _blank>here</A> to view your new Meta Subsystem</H3>";
  }
  else {
    $link .= "Could not create new Meta Subsystem $msname.</H3>";
  }
  return $link;
}

sub get_ms_subsets {
  my ( $bss ) = @_;

  my $ms_subsets;

  foreach my $line ( split( "\n", $bss ) ) {
    my ( $subsetname, $subsystem, $abb ) = split( "\t", $line );
    $ms_subsets->{ $subsetname }->{ $abb."##-##".$subsystem } = 1;
  }

  return $ms_subsets;

}

sub get_ms_genomes {
  my ( $fig, $cgi, $chosen_subsystems, $whichgenomes ) = @_;

  my %genomes;

  foreach my $ssname ( @$chosen_subsystems ) {
    my $sshandle = new Subsystem( $ssname, $fig, 0 );
    my @genomes_ss = $sshandle->get_genomes();
    foreach my $g ( @genomes_ss ) {
      my $gidx = $sshandle->get_genome_index( $g );
      my $variant = $sshandle->get_variant_code( $gidx );
      if ( $variant ne '-1' ) {
	$genomes{ $g }++;
      }
    }
  }
  if ( $whichgenomes eq 'all_in_seed' ) {
    return $fig->genomes();
  }
  if ( $whichgenomes eq 'all_in_field' ) {
    my @retarr = $cgi->param( 'sel_genome' );
    return \@retarr;
  }
  if ( $whichgenomes eq 'all_in_one' ) {
    my @retarr = keys %genomes;
    return \@retarr;
  }
  if ( $whichgenomes eq 'all_in_all' ) {
    my $numss = scalar( @$chosen_subsystems );
    my @retarr = ();
    foreach my $g ( keys %genomes ) {
      if ( $genomes{ $g } == $numss ) {
	push @retarr, $g;
      }
    }
    return \@retarr;
  }
  return [];
}

sub supported_rights {
  
  return [ [ 'edit', 'subsystem', '*' ] ];

}

