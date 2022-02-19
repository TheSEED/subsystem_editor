package SubsystemEditor::WebPage::ShowSubsystem;

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

  $self->application->register_component( 'Table', 'sstable'  );
  $self->application->register_component(  'Table', 'VarDescTable'  );
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

  my $fig = $self->application->data_handle( 'FIG' );
  my $cgi = $self->application->cgi;
  
  # subsystem name and 'nice name' #
  my $name = $cgi->param( 'subsystem' );
  $name = uri_unescape( $name );
  $name =~ s/&#39/'/g;
  my $ssname = $name;
  $ssname =~ s/\_/ /g;

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
    else {
      # we might have the problem that the user has not yet got the right for editing the
      # subsystem due to that it was created in the old seed or what do I know where.
      my $curatorOfSS = $fig->subsystem_curator( $name );
      my $su = lc( $seeduser );
      my $cu = lc( $curatorOfSS );
      if ( $su eq $cu ) {
	# now set the rights... 
	my $right = $dbmaster->Rights->create( { name => 'edit',
						 scope => $user->get_user_scope,
						 data_type => 'subsystem',
						 data_id => $name,
						 granted => 1,
						 delegated => 0 } );
	if ( $right ) {
	  $can_alter = 1;
	  $fig->set_user( $seeduser );
	}
      }
    }
  }

  ######################
  # Construct the menu #
  ######################

  my $menu = $self->application->menu();

  my $esc_name = uri_escape($name);

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

  $content .= "<H2>Subsystem Info</H2>";
  my $subsystem = new Subsystem( $name, $fig, 0 );

  if ( defined( $cgi->param( 'SUBMIT' ) ) ) {

    # set description and notes
    my $descrp = $cgi->param( 'SSDESC' );
    chomp $descrp;
    $descrp .= "\n";
    $subsystem->set_description( $descrp );
    my $notes = $cgi->param( 'SSNOTES' );
    chomp $notes;
    $notes .= "\n";
    $subsystem->set_notes( $notes );

    my $class1 = '';
    my $class2 = '';

    if ( defined( $cgi->param( 'Classification' ) ) ) {
      if ( $cgi->param( 'Classification' ) eq 'User-defined' ) {      
	if ( defined( $cgi->param( "SUBSYSH1TF" ) ) ) {
	  $class1 = $cgi->param( "SUBSYSH1TF" );
	}
      }
      else {
	if ( defined( $cgi->param( "SUBSYSH1" ) ) ) {
	  $class1 = $cgi->param( "SUBSYSH1" );
	}
      }
    }

    if ( defined( $cgi->param( 'Classification' ) ) ) {
      if ( $cgi->param( 'Classification' ) eq 'User-defined' ) {  
	if ( defined( $cgi->param( "SUBSYSH2TF" ) ) ) {
	  $class2 = $cgi->param( "SUBSYSH2TF" );
	}
      }
      else {
	if ( defined( $cgi->param( "SUBSYSH2" ) ) ) {
	  $class2 = $cgi->param( "SUBSYSH2" );
	}
      }
    }
    $subsystem->set_classification( [ $class1, $class2 ] );

    my $litstoset = $cgi->param( 'SUBSYSLIT' );
    $litstoset =~ s/ //g;
    my @lits = split( ',', $litstoset );
    setLiteratures( $fig, $name, \@lits );

    my $wlstoset = $cgi->param( 'SUBSYSWL' );
    if ( defined( $wlstoset ) && $wlstoset =~ /.+\s+.+/ ) {
      my @wls = split( '\n', $wlstoset );
      setWeblinks( $fig, $name, \@wls );
    }

    # here we really edit the files in the subsystem directory #
    $subsystem->incr_version();
    $subsystem->db_sync();
    $subsystem->write_subsystem();
  }
  elsif ( defined( $cgi->param( 'GrantRightButton' ) ) ) {
    if ( $can_alter && $user->has_right( undef, 'edit', 'subsystem', $name, 1 ) ) {
      my ($newAnno, $readable_name) = split(/\|/, $cgi->param( 'ANNOBOX' ));
      my $thisScopes = $dbmaster->Scope->get_objects( { _id => $newAnno } );
      if ( defined( $thisScopes->[0]) ) {

	my $rights = $dbmaster->Rights->get_objects( { name => 'edit',
						       data_type => 'subsystem',
						       data_id => $name,
						       scope => $thisScopes->[0] } );
	if ( defined( $rights->[0] ) ) {
	  $self->application->add_message( 'warning', "$readable_name already has the right to edit this subsystem." );
	}
	else {	
	  my $right = $dbmaster->Rights->create( { granted => 1,
						   delegated => 1,
						   name => 'edit',
						   data_type => 'subsystem',
						   data_id => $name,
						   scope => $thisScopes->[0] } );
	  if ( $right ) {
	    $self->application->add_message( 'info', "$readable_name can now edit this subsystem" );
	  }
	  else {
	    $self->application->add_message( 'warning', "Could not create right to edit the subsystem for $readable_name" );
	  }
	}
      }
    }
    else {
      $self->application->add_message( 'warning', "You do not have the right to share the subsystem." );
    }
  }
  elsif ( defined( $cgi->param( 'RevokeRightButton' ) ) ) {
    if ( $can_alter && $user->has_right( undef, 'edit', 'subsystem', $name, 1 ) ) {  
      my ($newAnno, $readable_name) = split(/\|/, $cgi->param( 'ALANNOBOX' ));
      my $thisScopes = $dbmaster->Scope->get_objects( { _id => $newAnno } );
      my $rights = $dbmaster->Rights->get_objects( { name => 'edit',
						     data_type => 'subsystem',
						     data_id => $name,
						     scope => $thisScopes->[0] } );
      
      my $thisRight = $rights->[0];
      if ( defined( $thisRight ) && $thisRight->delegated ) {
	$thisRight->delete();
	
	$self->application->add_message( 'info', "$readable_name cannot edit this subsystem any more." );
      }
      else {
	$self->application->add_message( 'warning', "You can't revoke the right of $readable_name to edit this subsystem." );	
      }
    }
    else {
      $self->application->add_message( 'warning', "You do not have the right to revoke rights for this subsystem." );
    }
  }
  
  $subsystem = new Subsystem( $name, $fig, 0 );

  $content .= $self->start_form( 'form', { subsystem => $name } );

  my ( $ssversion, $sscurator, $pedigree, $ssroles ) = $fig->subsystem_info( $name );

  my $versionlink = '';

  if ( $can_alter ) {
    $versionlink = " -- <A HREF='".$self->application->url()."?page=ResetSubsystem&subsystem=$esc_name'>Reset to Previous Timestamp</A>";
  }

  my $mod_time = get_mod_time( $name );
  my $class = $fig->subsystem_classification( $name );
  my $ssnotes = $subsystem->get_notes();

  if ( !defined( $ssnotes ) ) {
    $ssnotes = '';
  }
  my $ssdesc = $subsystem->get_description();

  if ( !defined( $ssdesc ) ) {
    $ssdesc = '';
  }

  my $classification_stuff;
  if ( $can_alter ) {
    $classification_stuff = get_classification_boxes( $fig, $cgi, $class->[0], $class->[1] );
  }
  else {
    $classification_stuff = "<TR><TH>Classification:</TH><TD>$class->[0]</TD></TR>";
    $classification_stuff .= "<TR><TH></TH><TD>$class->[1]</TD></TR>";
  }
  
  my $infotable = "<TABLE><TR><TH>Name:</TH><TD>$ssname</TD></TR>";
  $infotable .= "<TR><TH>Author:</TH><TD>$sscurator</TD></TR>";
  if ( $can_alter && $user->has_right( undef, 'edit', 'subsystem', $name, 1 ) && !$self->application->{anonymous_mode}) {

    my $annoGrp = $dbmaster->Scope->get_objects( { name => 'Annotators' } );
    my $annoScope = $dbmaster->UserHasScope->get_objects( { scope => $annoGrp->[0] } );
    my $annoMems = [];
    foreach my $aS ( @$annoScope ) {
      push @$annoMems, $aS->user();
    }
    @$annoMems = sort { $a->lastname cmp $b->lastname || $a->firstname cmp $b->firstname } @$annoMems;

    my $editRightButton = "<INPUT TYPE=SUBMIT ID='GrantRightButton' NAME='GrantRightButton' VALUE='Grant Right'>";
    my $revokeRightButton = "<INPUT TYPE=SUBMIT ID='RevokeRightButton' NAME='RevokeRightButton' VALUE='Revoke Right'>";

    my $user_has_scopes = $dbmaster->UserHasScope->get_objects( { user => $user });
    my $available_groups = {};
    foreach my $user_has_scope (@$user_has_scopes) {
      my $scope = $user_has_scope->scope();
      next if $scope->name() =~ /^user:/;
      next if $scope->name() =~/^Public/;
      $available_groups->{$scope->{_id}} = $scope;
    }
    my $all_ss_edit_rights = $dbmaster->Rights->get_objects( { name => 'edit',
							       data_type => 'subsystem',
							       data_id => $name } );
    my $user_groups_have_right = [];
    my $user_groups_not_have_right = [];
    foreach my $r (@$all_ss_edit_rights) {
      my $scope = $r->scope;
      next if $scope->name() =~ /^user:/;
      next if $scope->name() =~/^Public/;
      push(@$user_groups_have_right, [ $scope->_id, $scope->name ]);
      delete $available_groups->{$scope->{_id}};
    }
    foreach my $key (sort(keys(%$available_groups))) {
      my $scope = $available_groups->{$key};
      push(@$user_groups_not_have_right, [ $scope->_id, $scope->name ]);
    }

    my $annotatorsBox = "<SELECT NAME='ANNOBOX' ID='ANNOBOX'>";
    my $alreadyAnnotatorsBox = "<SELECT NAME='ALANNOBOX' ID='ALANNOBOX'>";
    foreach my $a ( @$user_groups_have_right ) {
      $alreadyAnnotatorsBox .= "<OPTION VALUE='".$a->[0]."|group ".$a->[1]."'>group ".$a->[1]."</OPTION>";
    }
    foreach my $a ( @$user_groups_not_have_right ) {
      $annotatorsBox .= "<OPTION VALUE='".$a->[0]."|group ".$a->[1]."'>group ".$a->[1]."</OPTION>";
    }
    foreach my $a ( @$annoMems ) {
      my $r = $dbmaster->Rights->get_objects( { name => 'edit',
						scope => $a->get_user_scope,
						data_type => 'subsystem',
						data_id => $name } );
      unless ( scalar(@$r) ) {
	$annotatorsBox .= "<OPTION VALUE='".$a->get_user_scope->_id."|".$a->firstname." ".$a->lastname."'>".$a->firstname.' '.$a->lastname.' ( '.$a->login." )</OPTION>";
      }
      else {
	if ( $a->login() ne $user->login() && ( ! $a->has_right( undef, 'edit', 'subsystem', '*' ) ) ) {
	  $alreadyAnnotatorsBox .= "<OPTION VALUE='".$a->get_user_scope->_id."|".$a->firstname." ".$a->lastname."'>".$a->firstname.' '.$a->lastname.' ( '.$a->login." )</OPTION>";
	}
      }
    }
    $annotatorsBox .= "</SELECT>";
    $alreadyAnnotatorsBox .= "</SELECT>";
      
    $infotable .= "<TR><TH>Grant Right To Edit To:</TH><TD>$annotatorsBox $editRightButton</TD></TR>";
    $infotable .= "<TR><TH>Revoke Right To Edit From:</TH><TD>$alreadyAnnotatorsBox $revokeRightButton</TD></TR>";
  }
  $infotable .= "<TR><TH>Version:</TH><TD>$ssversion $versionlink</TD></TR>";
  $infotable .= "<TR><TH>Last Modified:</TH><TD>$mod_time</TD></TR>";

  # Literature #
  my $lit = getLiteratures( $fig, $name );
  my $litstring = '';
  my $litvoid = '';
  if ( defined( $lit ) && scalar( @$lit ) > 0 ) {
    my @litlinks;
    foreach my $l ( @$lit ) {
      my $thislink = "<a href=\"javascript:void(0)\"onclick=\"window.open('https://pubmed.ncbi.nlm.nih.gov/$l/?dopt=Abstract')\">$l</a>";
      #my $thislink = "<a href=\"javascript:void(0)\"onclick=\"window.open('http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=retrieve&db=pubmed&list_uids=" . $l ."')\">$l</a>";
      push @litlinks, $thislink;
    }
    $litstring = join( ', ', @litlinks );
    $litvoid = join( ', ', @$lit );
  }

  # Weblinks #
  my ( $wl, $wlvoid ) = getLinks( $fig, $name );

  my $variants = $subsystem->get_variants();

  if ( $can_alter ) {

    my $editLitButton = "<INPUT TYPE=BUTTON ID='EditLitButton' VALUE='Edit Literature' ONCLICK='MakeEditableLit( \"0\" );'><INPUT TYPE=BUTTON ID='ShowLitButton' VALUE='Show Links' STYLE='display: none;' ONCLICK='MakeEditableLit( \"1\" );'>";
    my $editWLButton = "<INPUT TYPE=BUTTON ID='EditWLButton' VALUE='Edit Weblinks' ONCLICK='MakeEditableWL( \"0\" );'><INPUT TYPE=BUTTON ID='ShowWLButton' VALUE='Show Weblinks' STYLE='display: none;' ONCLICK='MakeEditableWL( \"1\" );'>";

    $infotable .= "<TR><TH>Literature</TH><TD><TABLE><TR><TD><SPAN ID='LitSpan'>$litstring</SPAN></TD><TD>$editLitButton</TD><TD><INPUT TYPE=TEXT STYLE='width: 200px; display: none;' NAME='SUBSYSLIT' ID='SUBSYSLIT' VALUE='$litvoid'></TD><TD><SPAN ID='TEXTSPAN' STYLE='display: none;'>Please enter the PubMed ID (PMID), and we will automatically get the paper information. Multiple PMIDs should be separated by \', \'</SPAN></TD></TR></TABLE></TD></TR>";
    $infotable .= "<TR><TH>Websites</TH><TD><TABLE><TR><TD><SPAN ID='WLSpan'>$wl</SPAN></TD><TD>$editWLButton</TD><TD><TEXTAREA ROWS=3 STYLE='width: 400px; display: none;' NAME='SUBSYSWL' ID='SUBSYSWL'>$wlvoid</TEXTAREA></TD><TD><SPAN ID='AREASPAN' STYLE='display: none;'>Please use the following format:<BR>Description of the first web page http://www.xyz.org/...<BR>Description of the second web page http://www.xzy.de/...</SPAN></TD></TR></TABLE></TD></TR>";
    $infotable .= "<TR><TH>Description</TH><TD><TEXTAREA NAME='SSDESC' ROWS=15 STYLE='width: 772px;'>$ssdesc</TEXTAREA></TD></TR>";
    $infotable .= "<TR><TH>Notes</TH><TD><TEXTAREA NAME='SSNOTES' ROWS=15 STYLE='width: 772px;'>$ssnotes</TEXTAREA></TD></TR>";
  }
  else {
    # do a little formating because the notes often contain many many blanks and newlines
    my $ssdesc_brs = $ssdesc;
    $ssdesc_brs =~ s/\n/<BR>/g;
    $ssdesc_brs =~ s/(\n\s)+/\n/g;
    my $ssnotes_brs = $ssnotes;
    $ssnotes_brs =~ s/(\n\s)+/\n/g;
    $ssnotes_brs =~ s/\n/<BR>/g;
    $infotable .= "<TR><TH>Literature</TH><TD>$litstring</TD></TR>";
    $infotable .= "<TR><TH>Websites</TH><TD>$wl</TD></TR>";
    $infotable .= "<TR><TH>Description</TH><TD>$ssdesc_brs</TD></TR>";
    $infotable .= "<TR><TH>Notes</TH><TD>$ssnotes_brs</TD></TR>";
  }
  # variants
  my $vartable = $self->application->component( 'VarDescTable' );
  $vartable->columns( [ { name => "Variant" }, { name => "Description" } ] );
  
  my $vardata;
  my $has_variants = 0;
  foreach my $kv ( sort keys %$variants ) {
    $has_variants = 1;
    push @$vardata, [ $kv, $variants->{ $kv } ];
  }
  $vartable->data( $vardata );
  $infotable .= "<TR><TH>Variants</TH><TD>";
  if ( $has_variants ) {
    $infotable .= $vartable->output();  
  }
  
  if ( $can_alter ) {
    my $variant_outside = "<INPUT TYPE=BUTTON VALUE='Edit Variants in Variant Overview' NAME='EditVariantsOverview' ID='EditVariantsOverview' ONCLICK='window.open( \"".$self->application->url()."?page=ShowVariants&subsystem=$name\" )'>";
  $infotable .= $variant_outside;
  }

  $infotable .= "</TD</TR>";

  $infotable .= $classification_stuff;
  $infotable .= "</TABLE>";

  if ( $can_alter ) {
    $infotable .= "<INPUT TYPE=SUBMIT VALUE='Save Changes' ID='SUBMIT' NAME='SUBMIT' STYLE='background-color: red;'>";
  }

  if ( $can_alter ) {
    $content .= "<INPUT TYPE=SUBMIT VALUE='Save Changes' ID='SUBMIT' NAME='SUBMIT'  STYLE='background-color: red;'>";
  }
  $content .= $infotable;
  $content .= $self->end_form();

  return $content;
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
      return $last_modified;
    }
  }
  return "$FIG_Config::data/Subsystems/$ssa/Backup";
}


sub get_classification_boxes {
  my ( $fig, $cgi, $class1, $class2 ) = @_;
  my $classified = 1;

  my $sdContent = '';
  my $SUBSYSH1 = $class1;
  my $SUBSYSH2 = $class2;

  # variables that monitor if we have selected a box
  my $putinh1 = 0;
  my $putinh2 = 0;

  if ( !defined( $SUBSYSH1 ) ){
    $putinh1 = 1;
  }
  if ( !defined( $SUBSYSH2 ) ){
    $putinh2 = 1;
  }

  my $inh1 = '';
  if ( defined( $cgi->param( 'SUBSYSH1TF' ) ) ) {
    $inh1 = $cgi->param( 'SUBSYSH1TF' );
  }
  elsif ( defined( $SUBSYSH1 ) ) {
    if ( !$putinh1 ) {
      $inh1 = $SUBSYSH1;
    }
  }
  my $inh2 = '';
  if ( defined( $cgi->param( 'SUBSYSH2TF' ) ) ) {
    $inh2 = $cgi->param( 'SUBSYSH2TF' );
  }
  elsif ( defined( $SUBSYSH2 ) ) {
    if ( !$putinh2 ) {
      $inh2 = $SUBSYSH2;
    }
  }

  my @ssclassifications = $fig->all_subsystem_classifications();
  my $ssclass;
  foreach my $ssc ( @ssclassifications ) {
    if ( !defined( $ssc->[1] ) ) {
      $ssc->[1] = '';
    }
#    next if ( ( !defined( $ssc->[0] ) ) || ( !defined( $ssc->[1] ) ) );
    next if ( !defined( $ssc->[0] ) );
    next if ( $ssc->[0] eq '' );
#    next if ( ( $ssc->[0] eq '' ) || ( $ssc->[1] eq '' ) );
    next if ( ( $ssc->[0] =~ /^\s+$/ ) || ( $ssc->[1] =~ /^\s+$/ ) );
    push @{ $ssclass->{ $ssc->[0] } }, $ssc->[1];
  }


  my @options;
  foreach my $firstc ( keys %$ssclass ) {
    my $opt = "<SELECT SIZE=5 ID='$firstc' NAME='SUBSYSH2' STYLE='width: 386px;' class='hideme'>";
    my $optstring = '';
    foreach my $secc ( sort @{ $ssclass->{ $firstc } } ) {
      if ( defined( $SUBSYSH2 ) && $SUBSYSH2 eq $secc && $SUBSYSH1 eq $firstc ) {
	$optstring .= "<OPTION SELECTED VALUE='$secc'>$secc</OPTION>";
	# we have to show the selectbox if there is a selected value
	$opt = "<SELECT SIZE=5 ID='$firstc' NAME='SUBSYSH2' STYLE='width: 386px;' class='showme'>";
	$putinh2 = 1;
      }
      else {
	$optstring .= "<OPTION VALUE='$secc'>$secc</OPTION>";
      }
    }
    $opt .= $optstring;
    $opt .= "</SELECT>";
    push @options, $opt;
  }

  if ( $classified ) {
    $sdContent .= "<TR><TH><INPUT TYPE=\"RADIO\" NAME=\"Classification\" VALUE=\"Classified\" CHECKED onchange='radioclassification();'>Classification:</TH><TD><SELECT SIZE=5 ID='SUBSYSH1' NAME='SUBSYSH1' STYLE='width: 386px;' onclick='gethiddenoption();'>";
  }
  else {
    $sdContent .= "<TR><TD><INPUT TYPE=\"RADIO\" NAME=\"Classification\" VALUE=\"Classified\" onchange='radioclassification();'>Classification:</TD><TD><SELECT SIZE=5 ID='SUBSYSH1' NAME='SUBSYSH1' STYLE='width: 386px;' onclick='gethiddenoption();' DISABLED=DISABLED>";
  }
  foreach my $firstc ( sort keys %$ssclass ) {
    if ( defined( $SUBSYSH1 ) && $SUBSYSH1 eq $firstc ) {
      $sdContent .= "\n<OPTION SELECTED VALUE='$firstc'>$firstc</OPTION>\n";
      $putinh1 = 1;
    }
    else {
      $sdContent .= "\n<OPTION VALUE='$firstc'>$firstc</OPTION>\n";
    }
  }
  $sdContent .= "</SELECT>";

  foreach my $opt ( @options ) {
    $sdContent .= $opt;
  }

  $sdContent .= "</TD></TR>";
  if ( $classified ) {
    $sdContent .= "<TR><TH><INPUT TYPE=\"RADIO\" NAME=\"Classification\" VALUE=\"User-defined\" onchange='radioclassification();'>User-defined:</TH><TD><INPUT TYPE=TEXT  STYLE='width: 386px;' NAME='SUBSYSH1TF' ID='SUBSYSH1TF' VALUE='' DISABLED=\"DISABLED\"><INPUT TYPE=TEXT  STYLE='width: 386px;' NAME='SUBSYSH2TF' ID='SUBSYSH2TF' VALUE='' DISABLED=DISABLED></TD></TR>";
  }
  else {
    $sdContent .= "<TR><TH><INPUT TYPE=\"RADIO\" NAME=\"Classification\" VALUE=\"User-defined\" CHECKED onchange='radioclassification();'>User-defined:</TH><TD><INPUT TYPE=TEXT  STYLE='width: 386px;' NAME='SUBSYSH1TF' ID='SUBSYSH1TF' VALUE='$inh1'><INPUT TYPE=TEXT  STYLE='width: 386px;' NAME='SUBSYSH2TF' ID='SUBSYSH2TF' VALUE='$inh2'></TD></TR>";
  }


  return $sdContent;
}

########################################
# get Literature-string for subsystems #
########################################
sub getLiteratures {
  my ( $fig, $name ) = @_;

  my $esc_name = uri_escape($name);

  my $frpubs;
  my @rel_lit_num = $fig->get_attributes( 'Subsystem:'.$name, "SUBSYSTEM_PUBMED_RELEVANT" );

  foreach my $k ( @rel_lit_num ) {
    my ( $ss, $key, $value ) = @$k;
    push @$frpubs, $value;
  }

  return $frpubs;
}

######################################
# get Weblinks-string for subsystems #
######################################
sub getLinks {
  my ( $fig, $name ) = @_;

  my $esc_name = uri_escape($name);

  my $links;
  my $linksstring = '';
  my $linksvoid = '';
  my @rel_link_num = $fig->get_attributes( 'Subsystem:'.$name, "SUBSYSTEM_WEBLINKS" );

  foreach my $k ( @rel_link_num ) {
    my ( $ss, $key, @value ) = @$k;
    $linksstring .= $value[0].": <a href=\"javascript:void(0)\"onclick=\"window.open('".$value[1]."','height=640,width=800,scrollbars=yes,toolbar=yes,status=yes')\">". $value[1]."</a><BR>";
    $linksvoid .= $value[0]." ".$value[1]."\n";
  }

  return ( $linksstring, $linksvoid );
}

########################################
# set Literature-string for subsystems #
########################################
sub setLiteratures {
  my ( $fig, $name, $newpubs ) = @_;

  my $esc_name = uri_escape($name);

  my @values;
  my @rel_lit_num = $fig->get_attributes( 'Subsystem:'.$name, "SUBSYSTEM_PUBMED_RELEVANT" );

  foreach my $k ( @rel_lit_num ) {
    my ( $ss, $key, $value ) = @$k;
    $fig->delete_matching_attributes( "Subsystem:$name", "SUBSYSTEM_PUBMED_RELEVANT" );
  }

  foreach my $np ( @$newpubs ) {
    $fig->add_attribute( "Subsystem:$name", "SUBSYSTEM_PUBMED_RELEVANT", $np );
  }  
}

########################################
# set Literature-string for subsystems #
########################################
sub setWeblinks {
  my ( $fig, $name, $newpubs ) = @_;

  my $esc_name = uri_escape($name);

  my @values;
  my @rel_lit_num = $fig->get_attributes( 'Subsystem:'.$name, "SUBSYSTEM_WEBLINKS" );

  foreach my $k ( @rel_lit_num ) {
    my ( $ss, $key, $value ) = @$k;
    $fig->delete_matching_attributes( "Subsystem:$name", "SUBSYSTEM_WEBLINKS" );
  }

  foreach my $np ( @$newpubs ) {
    #my @h = split( /\s+/, $np );
    $np =~ s/\s*(http\S+)\s*//;
    my $link=$1;
    if ($np =~ /^\s*$/) {$np = "webpage"}
    $fig->add_attribute( "Subsystem:$name", "SUBSYSTEM_WEBLINKS", $np, $link );
    print STDERR "Adding attribute 'Subsystem:$name' 'SUBSYSTEM_WEBLINKS', '$np', '$link'\n";
  }  
}

sub supported_rights {
  
  return [ [ 'edit', 'subsystem', '*' ] ];

}

