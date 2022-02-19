package SubsystemEditor::WebPage::ShowFunctionalRoles;

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

  $self->application->register_component(  'Table', 'sstable'  );
  $self->application->register_component( 'HelpLink', 'HelpSubsets' );
}

sub require_javascript {

  return [ './Html/showfunctionalroles.js' ];

}

##############################################
# Website content is returned by this method #
##############################################
sub output {
  my ( $self ) = @_;
  
  $self->{ 'fig' } = $self->application->data_handle( 'FIG' );
  $self->{ 'cgi' } = $self->application->cgi;
  
  my $name = $self->{ 'cgi' }->param( 'subsystem' );
  my $ssname = $name;
  $ssname =~ s/\_/ /g;

  my $esc_name = uri_escape($name, "^A-Za-z0-9\-_.!~*()");

  # look if someone is logged in and can write the subsystem #
  $self->{ 'can_alter' } = 0;
  my $user = $self->application->session->user;
  if ( $user && $user->has_right( $self->application, 'edit', 'subsystem', $name ) ) {
    $self->{ 'can_alter' } = 1;
  }

  my $dbmaster = $self->application->dbmaster;
  my $ppoapplication = $dbmaster->Backend->init( { name => 'SubsystemEditor' } );
  
  # get a seeduser #
  $self->{ 'seeduser' } = '';
  if ( defined( $user ) && ref( $user ) ) {
    my $preferences = $dbmaster->Preferences->get_objects( { user => $user,
							     name => 'SeedUser',
							     application => $ppoapplication } );
    if ( defined( $preferences->[0] ) ) {
      $self->{ 'seeduser' } = $preferences->[0]->value();
    }
  }

  if ( $user && $user->has_right( $self->application, 'edit', 'subsystem', $name ) ) {
    $self->{ 'can_alter' } = 1;
    $self->{ 'fig' }->set_user( $self->{ 'seeduser' } );
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
 
  
  ###############################
  # Get Existing Subsystem Data #
  ###############################

  my ( $frshash, $different_react_hope, $addrolehash, $comment, $error );
  my $addcomment = '';
  my $subsetstatus = 1;
  my $gostatus = 1;
  my $literaturestatus = 1;
  
  my $cgi = $self->{cgi};

  if ( defined($cgi->param('DoReorder')) || defined($cgi->param("DoReorder.x"))) {
    # just reordering the functional roles #
    ( $frshash, $different_react_hope, $addrolehash, $comment, $error ) = $self->getFunctionalRolesCgi( $name, 0 );
    $subsetstatus = $cgi->param( 'SUBSETSTATUS' );
    $gostatus = $cgi->param( 'GOSTATUS' );
    $literaturestatus = $cgi->param( 'LITERATURESTATUS' );
  }
  elsif ( defined( $cgi->param( 'AddRole' ) ) || defined( $cgi->param( 'AddRole.x' ) ) ) {
    # adding a role #
    ( $frshash, $different_react_hope, $addrolehash, $comment, $error ) = $self->getFunctionalRolesCgi( $name, 1 );
    $addcomment .= "To confirm the changes, please use the button \'Save changes\'";
    $subsetstatus = $cgi->param( 'SUBSETSTATUS' );
    $gostatus = $cgi->param( 'GOSTATUS' );
    $literaturestatus = $cgi->param( 'LITERATURESTATUS' );
  }
  elsif ( defined( $cgi->param( 'SubmitChangesToRoles' ) ) ) {
    # write functional role data into subsystem #
    ( $frshash, $different_react_hope, $addrolehash, $comment, $error ) = $self->getFunctionalRolesCgi( $name, 0 );
    my ( $putcomment, $puterror ) = $self->writeSubsystem( $frshash, $name );
    $addcomment .= $putcomment;
    $error .= $puterror;

    if ( $error eq '' ) {
      ( $frshash, $different_react_hope, $addrolehash, $comment, $error ) = $self->getFunctionalRoles( $name );
    }
  }
  else {
    ( $frshash, $different_react_hope, $addrolehash, $comment, $error ) = $self->getFunctionalRoles( $name );
  }

  my @indices = sort { $a <=> $b } keys %$frshash;

  ##############################
  # Construct the page content #
  ##############################

  my $content = "<H1>Functional Roles:  $ssname</H1>";
  $content .= $self->start_form( 'frform', { subsystem => $name } );

  my $frtable;

  if ( $self->{ 'can_alter' } ) {
    $frtable = $self->getEditableFRTable( \@indices, $frshash, $different_react_hope, $addrolehash, $subsetstatus, $gostatus, $literaturestatus, $name );
  }
  else {
    $frtable = $self->getNonEditableFRTable( \@indices, $frshash, $different_react_hope, $name );
  }

  $content .= $frtable;

  $content .= $self->end_form();


  ###############################
  # Display errors and comments #
  ###############################
 
  if ( defined( $error ) && $error ne '' ) {
    $self->application->add_message( 'warning', $error );
  }
  if ( defined( $comment ) && $comment ne '' ) {
    $comment .= $addcomment;
    $self->application->add_message( 'info', $comment );
  }

  return $content;
}

#############################
# write data into subsystem #
#############################
sub writeSubsystem {
  my ( $self, $frhash, $name ) = @_;
  
  # create a new subsystem object #
  my $subsystem = new Subsystem( $name, $self->{ 'fig' }, 0 );

  # build hashes/arrays for reactions, roles and subsets #
  my $reactionshash;
  my @newRoles;
  my $subsetshash;
  foreach my $index ( sort{ $a <=> $b } keys %$frhash ) {
    my $thisrole = $frhash->{ $index }->{ 'role' };
    if ( defined( $frhash->{ $index }->{ 'reaction' } ) ) {
      $reactionshash->{ $thisrole } = $frhash->{ $index }->{ 'reaction' };
    }
    my $thissubsets = $frhash->{ $index }->{ 'subsets' };
    foreach my $ssarrk ( @$thissubsets ) {
      if ( $ssarrk ne '' ) {
	push @{ $subsetshash->{ $ssarrk } }, $thisrole;
      }
    }
    push @newRoles, [ $thisrole, $frhash->{ $index }->{ 'abbr' } ];
  }
  
  # put roles into subsystem object #
  $subsystem->set_roles( \@newRoles  );
  
  # now put in reactions #
  foreach my $r ( keys %$reactionshash ) {
    $subsystem->set_reaction( $r, $reactionshash->{ $r } );
  }

  # delete old subsetes
  foreach my $s ( $subsystem->get_subset_namesC ) {
    next if ( $s eq "All" );
    $subsystem->delete_subsetC( $s );
  }

  # put in subsets #
  foreach my $ssarrk ( keys %$subsetshash ) {
    $subsystem->set_subsetC( $ssarrk, $subsetshash->{ $ssarrk } );
  }

  # here we really edit the files in the subsystem directory #
  $subsystem->incr_version();
  $subsystem->db_sync();
  $subsystem->write_subsystem();

  return( "Saved Subsystem\n", '' );
}


########################################
# Functional Role Table - not editable #
########################################
sub getNonEditableFRTable {

  my ( $self, $indices, $frshash, $different_react_hope, $name ) = @_;

  my $esc_name = uri_escape($name, "^A-Za-z0-9\-_.!~*()");

  ## TABLE HEADER ##    
  my $table = "<TABLE>\n";
  $table .= "<TR><TH>#</TH><TH NAME='SUBSETCOLUMN'";
  $table .= ">Subsets</TH><TH>Abbrev.</TH><TH>Functional Role</TH>";
  
  if ( $different_react_hope ) {
    $table .= "<TH>Role Reactions</TH><TH>Hope Reactions</TH>";
  }
  else {
    $table .= "<TH>Role/Hope Reactions</TH>";
  }

  $table .= "<TH NAME='GOCOLUMN'";
  $table .= ">GO Nr.</TH><TH NAME='LITERATURECOLUMN'";
  $table .= ">Literature</TH>";
  $table .= "</TR>";

  foreach my $roleindex ( @$indices ) {
    my $frname = $frshash->{ $roleindex }->{ 'role' };
    my $esc_frname = uri_escape($frname, "^A-Za-z0-9\-_.!~*()");

    $table .= "<TR><TD>$roleindex</TD>";
    my $subsetsstring = '';
    if ( defined( $frshash->{ $roleindex }->{ 'subsets' } ) ) {
      $subsetsstring = join( ', ', @{ $frshash->{ $roleindex }->{ 'subsets' } } );
    }
    $table .= "<TD>$subsetsstring</TD>";
    my $abbr = $frshash->{ $roleindex }->{ 'abbr' };
    my $alink = "ss_directed_compare_regions.cgi?ss=$esc_name&abbr=$abbr";
  
    $table .= "<TD><a href='$alink' target='_blank'>$abbr</a></TD>\n";
    $table .= qq~<TD><A HREF="SubsysEditor.cgi?page=FunctionalRolePage&subsystem=$esc_name&fr=$esc_frname" target=_blank>$frname</A></TD>~;
    $table .= "\n<TD>$frshash->{ $roleindex }->{ 'reactionhtml' }</TD>\n";

    if ( $different_react_hope ) {
      $table .= "<TD>$frshash->{ $roleindex }->{ 'hopereactionhtml' }</TD>";
    }

    ## GO TERMS ##
    $table .= "<TD>$frshash->{ $roleindex }->{ 'gos' }</TD>\n";

    ## LITERATURE ##
    if ( defined( $frshash->{ $roleindex }->{ 'literatures' } ) ) {
      $table .= "<TD>$frshash->{ $roleindex }->{ 'literatures' }</TD>";
    }
    else {
      $table .= "<TD></TD>";
    }
    $table .= "</TR>\n";
  }

  $table .= "</TR></TABLE>";

  return $table;
}


####################################
# Functional Role Table - editable #
####################################
sub getEditableFRTable {

  my ( $self, $indices, $frshash, $different_react_hope, $addrolehash, $subsetstatus, $gostatus, $literaturestatus, $name ) = @_;
  my $make_hope_extra = 1;

  my $cgi = $self->{cgi};
  
  # Subsets help component
  my $help_subsets = $self->application->component( 'HelpSubsets' );
  $help_subsets->hover_width( 300 );
  $help_subsets->wiki( 'http://biofiler.mcs.anl.gov/wiki/index.php/' );
  $help_subsets->page( 'SubsystemEditor:Subsets' );
  $help_subsets->title( 'Edit Subsets' );
  $help_subsets->text( "Put in the subsets a functional role belongs to. If a functional role is included in more than one subset, put them in delimited by \', \' (comma, space)" );

  ## TABLE HEADER ##    
  my $table = "<TABLE>\n";
  $table .= "<TR><TD COLSPAN=2><INPUT TYPE=SUBMIT ID='SubmitChangesToRoles' NAME='SubmitChangesToRoles' VALUE='SAVE CHANGES' STYLE='font-weight: bold; background-color: red;'></TD></TR>";
  $table .= "<TR><TH>#</TH><TH NAME='SUBSETCOLUMN'";
  if ( !$subsetstatus ) {
    $table .= " STYLE='display: none;'";
  }
  $table .= qq~>Subsets ~;
  $table .= $help_subsets->output();
  $table .= qq~ <IMG HSPACE='5' NAME='HIDESUBSETIMAGE' ID='HIDESUBSETIMAGE' WIDTH='25' HEIGHT='10' SRC='Html/hide.png' ALT='Hide' ONCLICK='HideWhat( "SUBSET" );' STYLE='cursor: pointer;'></TH><TH>Abbrev.</TH><TH COLSPAN=3>Functional Role</TH>~;
  
  if ( $different_react_hope ) {
    $table .= "<TH COLSPAN=2>Role Reactions</TH><TH>Hope Reactions</TH>";
  }
  else {
    $table .= "<TH COLSPAN=2>Role/Hope Reactions</TH>";
  }

  $table .= "<TH NAME='GOCOLUMN'";
  if ( !$gostatus ) {
    $table .= " STYLE='display: none;'";
  }
  $table .= qq~>GO Nr. <IMG HSPACE='5' NAME='HIDEGOIMAGE' ID='HIDEGOIMAGE' WIDTH='25' HEIGHT='10' SRC='Html/hide.png' ALT='Hide' ONCLICK='HideWhat( "GO" );' STYLE='cursor: pointer;'></TH><TH NAME='LITERATURECOLUMN'~;
  if ( !$literaturestatus ) {
    $table .= " STYLE='display: none;'";
  }
  $table .= qq~> Literature <IMG HSPACE='5' NAME='HIDELITERATUREIMAGE' ID='HIDELITERATUREIMAGE' WIDTH='25' HEIGHT='10' SRC='Html/hide.png' ALT='Hide' ONCLICK='HideWhat( "LITERATURE" );' STYLE='cursor: pointer;'></TH></TR>~;


  my $lastindex = 0;
  my $runningindex = 1;
  
  # lines for each already existing functional role #
  foreach my $roleindex ( @$indices ) {

    ## INDEX COLUMN ##
    my $frname = $frshash->{ $roleindex }->{ 'role' };
#    $frname =~ s/ /\_/g;
    $table .= "<TR><TD><SPAN ID='spanindexfr$runningindex' NAME='spanindexfr'>$runningindex</SPAN>\n";
    $table .= "<INPUT TYPE=TEXT ID='textindexfr$runningindex' STYLE='width: 30px; display: none;' NAME='textindexfr' VALUE='$runningindex'></TD>";

    ## SUBSET COLUMN ##
    my $subsetsstring = '';
    if ( defined( $frshash->{ $roleindex }->{ 'subsets' } ) ) {
      $subsetsstring = join( ', ', @{ $frshash->{ $roleindex }->{ 'subsets' } } );
    }
    $table .= "<TD NAME='SUBSETCOLUMN' ";
    if ( !$subsetstatus ) {
      $table .= " STYLE='display: none;'";
    }
    $table .= "><SPAN STYLE='display: none;' NAME='spanmesubset' ID='spanmesubset$runningindex'>$subsetsstring</SPAN>\n";
    $table .= $cgi->textfield( -id => "SUBSETCOLUMNTEXT$runningindex", -name => "SUBSETCOLUMNTEXT", -size => 14, -value => $subsetsstring, -override => 1 );

    ## ABBREVIATION COLUMN ##
    $table .= "<TD><SPAN STYLE='display: none;' NAME='spanmeabbr' ID='spanmeabbr$runningindex'>$frshash->{ $roleindex }->{ 'abbr' }</SPAN>\n";
    $table .= $cgi->textfield( -name => "FRAB", -size => 7, -value => $frshash->{ $roleindex }->{ 'abbr' }, -override => 1);

    ## ROLE COLUMN ##
    $table .= "<TD><SPAN STYLE='display: none;' NAME='spanmerole' ID='spanmerole$runningindex'>$frshash->{ $roleindex }->{ 'role' }</SPAN>\n";
    $table .= $cgi->textfield( -name => "FR", -size => 50, -value => $frshash->{ $roleindex }->{ 'role' }, -override => 1);
    my $esc_frname = uri_escape($frname, "^A-Za-z0-9\-_.!~*()"); # note this encodes ' as well which is critical here. See perldoc URI::Escape
    my $esc_name = uri_escape($name, "^A-Za-z0-9\-_.!~*()");

    ## SHOW FUNCTIONAL ROLE BUTTON ##

    $table .= qq~</TD><TD><IMG SRC='Html/showfr.png' ALT='ShowFR' NAME='SHOWFRIMAGE' ID='showfrmefr$runningindex' HEIGHT='15' VALUE='ShowFR' ONCLICK='window.open( \"~.$self->application->url().qq~?page=FunctionalRolePage&subsystem=$esc_name&fr=$esc_frname\", \"Functional Role Page\" )' STYLE='cursor: pointer'></TD>~;

    #
    # Show compared regions
    #
    my $abbr = $frshash->{ $roleindex }->{ 'abbr' };
    my $alink = "ss_directed_compare_regions.cgi?ss=$esc_name&abbr=$abbr";
    $table .= "<td><a target='_blank' href='$alink'>Compare Regs</a></td>\n";

    ## REACTION COLUMN ##
    $table .= "<TD><SPAN ID='spanmefr$runningindex'>$frshash->{ $roleindex }->{ 'reactionhtml' }</SPAN>\n";
    $table .= "<INPUT TYPE=TEXT ID='textmefr$runningindex' STYLE='width: 180px; display: none;' NAME='FRRE' VALUE='$frshash->{ $roleindex }->{ 'reaction' }'></TD>\n";
  # image edit and not displayed image ok #
    $table .= "<TD><IMG SRC='Html/edit.png' ALT='Edit' ID='reeditmefr$runningindex' WIDTH='30' HEIGHT='15' VALUE='Edit' ONCLICK='MakeEditableFR( \"mefr$runningindex\", \"0\" );' STYLE='cursor: pointer'> <IMG SRC='Html/ok.png' ALT='OK' ID='reokmefr$runningindex' WIDTH='30' HEIGHT='15' VALUE='Edit' ONCLICK='MakeEditableFR( \"mefr$runningindex\", \"1\" );' STYLE='display: none; cursor: pointer'>\n";

    if ( $different_react_hope ) {
      ## HOPE REACTION COLUMN ##
      $table .= "</TD><TD><SPAN ID='spanmehr$runningindex'";
      # make field red if hope reaction is not the same as reaction
      if ( $frshash->{ $roleindex }->{ 'hopereaction' } ne $frshash->{ $roleindex }->{ 'reaction' } ) {
	$table .= " STYLE='background-color: #fdabb6'";
      }

      $table .= ">$frshash->{ $roleindex }->{ 'hopereactionhtml' }</SPAN>\n";
      $table .= "<INPUT TYPE=TEXT ID='textmehr$runningindex' STYLE='width: 180px; display: none;' NAME='FRHR' VALUE='$frshash->{ $roleindex }->{ 'hopereaction' }'></TD>\n";
      # image edit and not displayed image ok - not wanted at the moment as hope reactions are not edited by annotators #
      # $table .= "<TD><IMG SRC='Html/edit.png' ALT='Edit' ID='reeditmehr$runningindex' WIDTH='30' HEIGHT='15' VALUE='Edit' ONCLICK='MakeEditableFR( \"mehr$runningindex\", \"0\" );' STYLE='cursor: pointer'> <IMG SRC='Html/ok.png' ALT='OK' ID='reokmehr$runningindex' WIDTH='30' HEIGHT='15' VALUE='Edit' ONCLICK='MakeEditableFR( \"mehr$runningindex\", \"1\" );' STYLE='display: none; cursor: pointer'></TD>\n";
    }
    else {
      # we put a hidden field in, so that the values will be give after submission
      $table .= "<INPUT TYPE=HIDDEN ID='textmehr$runningindex' NAME='FRHR' VALUE='$frshash->{ $roleindex }->{ 'hopereaction' }'>";
    }
    $table .= "</TD>";
    
    ## GO TERMS ##
    $table .= "<TD NAME='GOCOLUMN'>$frshash->{ $roleindex }->{ 'gos' }</TD>\n";
    
    ## LITERATURE ##
    if ( defined( $frshash->{ $roleindex }->{ 'literatures' } ) ) {
      $table .= "<TD NAME='LITERATURECOLUMN'>$frshash->{ $roleindex }->{ 'literatures' }</TD>";
    }
    else {
      $table .= "<TD></TD>";
    }
    $table .= "</TR>";
    
    $lastindex = $runningindex;
    $runningindex++;
  }

  # put button in for shuffling roles and submitting edits
  $table .= "<TR><TD COLSPAN=7><IMG SRC='Html/reorderroles.png' HEIGHT='20' ALT='ReorderRoles' ONCLICK='MakeEditableReordering();' ID='ReorderRoles' VALUE='Reorder Roles' STYLE='cursor: pointer;'><INPUT TYPE=IMAGE SRC='Html/doreorder.png' HEIGHT='20' ALT='DoReorderRoles' ID='DoReorder' NAME='DoReorder' VALUE='Do Reorder' STYLE='display: none; cursor: pointer;'></TD></TR>";
  
  # some info for adding a functional role #
  $table .= "<TR ID='ADDROLETEXTTR'><TD COLSPAN=7>Add a new role here. If you want the new role to be inserted into the Functional Role table, edit the index field<BR>to the index of the field it should appear in.</TD><TR>\n";

  # last line for adding a functional role #
  $lastindex++;

  my $fradd = '';
  my $frabadd = '';
  my $subsetadd = '';
  my $frreadd = '';
  my $frhradd = '';
  my $frreaddhtml = '';
  my $frhraddhtml = '';
  if ( defined( $addrolehash ) ) {
    $fradd = $addrolehash->{ 'role' };
    $frabadd = $addrolehash->{ 'abbr' };
    $subsetadd = $addrolehash->{ 'subset' };
    $frreadd = $addrolehash->{ 'reaction' };
    $frreaddhtml = $addrolehash->{ 'reactionhtml' };
    $frhradd = $addrolehash->{ 'hopereaction' };
    $frhraddhtml = $addrolehash->{ 'hopereactionhtml' };
  }
  
  ## INDEX COLUMN ##
  $table .= "<TR ID='NEWROLETR'><TD><INPUT TYPE=TEXT STYLE='width: 30px;' NAME='FRINDEXADD' VALUE='$lastindex'></TD>";

  ## SUBSET COLUMN ##
  $table .= "<TD NAME='SUBSETCOLUMN' ";
  if ( !$subsetstatus ) {
    $table .= " STYLE='display: none;'";
  }
  $table .= "><INPUT TYPE=TEXT ID='SUBSETCOLUMNTEXT$lastindex' STYLE='width: 100px;' NAME='SUBSETCOLUMNTEXTADD' VALUE='$subsetadd'></TD>";
  
  ## ABBREVIATION COLUMN ##
  $table .= "<TD>";
  $table .= $cgi->textfield( -name => "FRABADD", -size => 6, -value => $frabadd, -override => 1 );
  $table .= "</TD>\n";

  ## ROLE COLUMN ##
  $table .= "<TD COLSPAN=2>";
  $table .= $cgi->textfield( -name => "FRADD", -size => 50, -value => $fradd, -override => 1 );
  $table .= "</TD>\n";

  ## REACTION COLUMN ##
  $table .= "<TD><SPAN ID='spanmefr$lastindex'>$frreaddhtml</SPAN> <INPUT TYPE=TEXT ID='textmefr$lastindex' STYLE='width: 180px; display: none;' NAME='FRREADD' VALUE='$frreadd'></TD>";
  # image edit and not displayed image ok #
  $table .= "<TD><IMG SRC='Html/edit.png' ALT='Edit' ID='reeditmefr$lastindex' WIDTH='30' HEIGHT='15' VALUE='Edit' ONCLICK='MakeEditableFR( \"mefr$lastindex\", \"0\" );' STYLE='cursor: pointer;'> <IMG SRC='Html/ok.png' ALT='OK' ID='reokmefr$lastindex' WIDTH='30' HEIGHT='15' VALUE='Edit' ONCLICK='MakeEditableFR( \"mefr$lastindex\", \"1\" );' STYLE='display: none; cursor: pointer;'></TD>\n";

  if ( $different_react_hope ) {
    ## HOPE REACTION COLUMN ##
    $table .= "<TD><SPAN ID='spanmehr$lastindex'>$frhraddhtml</SPAN> <INPUT TYPE=TEXT ID='textmehr$lastindex' STYLE='width: 180px; display: none;' NAME='FRHRADD' VALUE='$frhradd'></TD>";
    # image edit and not displayed image ok - not wanted at the moment as hope reactions are not edited by annotators #
    # $table .= "<TD><IMG SRC='Html/edit.png' ALT='Edit' ID='reeditmehr$lastindex' WIDTH='30' HEIGHT='15' VALUE='Edit' ONCLICK='MakeEditableFR( \"mehr$lastindex\", \"0\" );' STYLE='cursor: pointer;'> <IMG SRC='Html/ok.png' ALT='OK' ID='reokmehr$lastindex' WIDTH='30' HEIGHT='15' VALUE='Edit' ONCLICK='MakeEditableFR( \"mehr$lastindex\", \"1\" );' STYLE='display: none; cursor: pointer;'></TD>\n";
  }

  # end of table
  $table .= "</TR></TABLE>";

  # now the functionality -> Buttons

  $table .= "<TABLE ID='BOTTOMBUTTONTABLE'><TR>";

  $table .= "<TD><INPUT TYPE='image' SRC='Html/addrole.png' HEIGHT='20' ALT='AddRole' NAME='AddRole' ID='AddRole' VALUE='Add Role' STYLE='cursor: pointer;'></TD>";

  $table .= "</TR></TABLE><TABLE><TR>\n";

  $table .= qq~<TD><IMG NAME='SHOWSUBSETIMAGE' ID='SHOWSUBSETIMAGE' HEIGHT='20' SRC='Html/showsubsets.png' ALT='ShowSubsets' ONCLICK='ShowWhat( "SUBSET" );' STYLE='cursor: pointer;~;
  if ( $subsetstatus ) {
    $table .= "display: none;";
  }
  $table .= "'></TD>\n";

  $table .= qq~<TD><IMG NAME='SHOWGOIMAGE' ID='SHOWGOIMAGE' HEIGHT='20' SRC='Html/showgo.png' ALT='ShowGO' ONCLICK='ShowWhat( "GO" );' STYLE='cursor: pointer;~;
  if ( $gostatus ) {
    $table .= "display: none;";
  }
  $table .= "'></TD>\n";

  $table .= qq~<TD><IMG NAME='SHOWLITERATUREIMAGE' ID='SHOWLITERATUREIMAGE' HEIGHT='20' SRC='Html/showliterature.png' ALT='ShowLiterature' ONCLICK='ShowWhat( "LITERATURE" );' STYLE='cursor: pointer;~;

  if ( $gostatus ) {
    $table .= "display: none;";
  }
  $table .= "'></TD>\n";

  $table .= "</TR></TABLE><TABLE><TR>\n";

  $table .= "<TD><INPUT TYPE=SUBMIT ID='SubmitChangesToRoles' NAME='SubmitChangesToRoles' VALUE='SAVE CHANGES' STYLE='font-weight: bold; background-color: red;'></TD>";
  
  $table .= "</TR></TABLE>";
  
  # hidden input types
  $table .= "<INPUT TYPE='HIDDEN' NAME='SUBSETSTATUS' ID='SUBSETSTATUS' VALUE='$subsetstatus'>";
  $table .= "<INPUT TYPE='HIDDEN' NAME='GOSTATUS' ID='GOSTATUS' VALUE='$gostatus'>";
  $table .= "<INPUT TYPE='HIDDEN' NAME='LITERATURESTATUS' ID='LITERATURESTATUS' VALUE='$literaturestatus'>";

  return $table;
}


#########################################
# Subsets of Roles Table - not editable #
#########################################
sub getEditableSSRTable {

  my ( $self, $indices, $frshash, $subsethash ) = @_;

  my $table = "<TABLE>
  <TR><TH>Subset.</TH><TH>Includes these functional Roles</TH></TR>";
  
  foreach my $subsetname ( keys %$subsethash ) {
    $table .= "<TR><TD>$subsetname</TD>";
    
    my $frsting = "";
    my $frmouseover = "";
    my $first = 1;

    foreach my $key ( sort { $a <=> $b } keys %{ $subsethash->{ $subsetname } } ) {
      if ( $first ) {
	$first = 0;
      }
      else {
	$frsting .= ', ';
	$frmouseover .= ",<BR>";
      }
      
      $frsting .= $key;

      $frmouseover .= '(' . $key . ') ';
      $frmouseover .= $subsethash->{ $subsetname }->{ $key };

    }

    $table .= "<TD onMouseover=\"javascript:if(!this.tooltip) this.tooltip=new Popup_Tooltip( this, 'Functional Role', '".$frmouseover."', '');this.tooltip.addHandler();return true;\" style='width: 22px; height: 22px;'>$frsting</TD>\n";   
  }

  $table .= "</TR></TABLE>";

  return $table;
}

#############################################################
# Construct a hash containing all info for functional roles #
# Point to edit backend functions if someone decides so :)  #
#############################################################
sub getFunctionalRolesCgi {

  my ( $self, $name, $addrole ) = @_;

  my $comment = '';
  my $error = '';

  my $frshash;
  my $addrolehash;
  my $rolenamehash;
  my $roleabkhash;

  my @textindexfrarray = $self->{ 'cgi'}->param( 'textindexfr' );
  my @SUBSETarray = $self->{ 'cgi' }->param( 'SUBSETCOLUMNTEXT' );
  my @FRarray = $self->{ 'cgi' }->param( 'FR' );
  my @FRABarray = $self->{ 'cgi' }->param( 'FRAB' );
  my @FRREarray = $self->{ 'cgi' }->param( 'FRRE' );
  my @FRHRarray = $self->{ 'cgi' }->param( 'FRHR' );

  my $frpubs = $self->getLiteratures( $name, \@FRarray );
  my $frgo = $self->getGOs( $name, \@FRarray );

  my $counter = 0;
  my $subkey = 1;
  my $different_react_hope = 0;

  foreach my $item ( @textindexfrarray ) {

    # question if item is a number 
    if ( !defined( $item ) || $item !~ /^\d+\.?\d*$/ ) {
      $item = '0';
    }

    my $key = $item;
    if ( exists( $frshash->{ $item } ) ) {
      $key = $item.".$subkey";
      $subkey++;
    }

    my $reacthtml = '';
    my $hopereacthtml = '';
    if ( $FRHRarray[ $counter ] ) {
      $hopereacthtml = join( ", ", map { &HTML::reaction_link( $_ ) } split( ', ', $FRHRarray[ $counter ] ) );
    }
    if ( $FRREarray[ $counter ] ) {
      $reacthtml = join( ", ", map { &HTML::reaction_link( $_ ) } split( ', ', $FRREarray[ $counter ] ) );
    }

    if ( $FRREarray[ $counter ] ne $FRHRarray[ $counter ] ) {
      $different_react_hope = 1;
    }

    if ( defined( $FRABarray[ $counter ] ) && ( $FRABarray[ $counter ] ne '' ) && defined( $FRarray[ $counter ] ) && ( $FRarray[ $counter ] ne '' ) ) {
      my @subsets = split( ', ', $SUBSETarray[ $counter ] );

      $frshash->{ $key } = { 'role' => $FRarray[ $counter ],
			     'subsets' => \@subsets,
			     'abbr' => $FRABarray[ $counter ],
			     'reaction' => $FRREarray[ $counter ],
			     'reactionhtml' => $reacthtml,
			     'hopereaction' => $FRHRarray[ $counter ],
			     'hopereactionhtml' => $hopereacthtml,
			     'literatures' => $frpubs->{ $FRarray[ $counter ] },
			     'gos' => $frgo->{ $FRarray[ $counter ] } };
      
      $rolenamehash->{ $FRarray[ $counter ] } = 1;
      $roleabkhash->{ $FRABarray[ $counter ] } = 1;
    }
    else {
      $comment .= "Deleted functional role number $counter.<BR>\n";
    }

    $counter++;
  }

  ############################
  # look for added role here #
  ############################

  my $putintoaddrole = 0;

  if ( $addrole ) {
    my $frindexadd = $self->{ 'cgi' }->param( 'FRINDEXADD' );
    my $subsetadd = $self->{ 'cgi' }->param( 'SUBSETCOLUMNTEXTADD' );
    my $fradd = $self->{ 'cgi' }->param( 'FRADD' );
    my $frabadd = $self->{ 'cgi' }->param( 'FRABADD' );
    my $frreadd = $self->{ 'cgi' }->param( 'FRREADD' );
    my $frhradd = $self->{ 'cgi' }->param( 'FRHRADD' );
    my $frpubs = $self->getLiteratures( $name, [ $fradd ] );
    my $frgo = $self->getGOs( $name, [ $fradd ] );

    if ( !defined( $frindexadd ) ) {
      $frindexadd = $counter++;
    }
    if ( !defined( $fradd ) || $fradd eq '' ) {
      $error .= "The Functional Role you added must have an abbreviation. Please state one!<BR>\n";
      $putintoaddrole = 1;
    }
    if ( !defined( $frabadd ) || $frabadd eq '' ) {
      $error .= "The Functional Role you added must have a role name. Please state one!<BR>\n";
      $putintoaddrole = 1;
    }
    if ( defined( $rolenamehash->{ $fradd } ) ) {
      $error .= "The Functional Role's name you try to add already exists and can't be added therefore<BR>\n";
      $putintoaddrole = 1;
    }
    if ( defined( $roleabkhash->{ $frabadd } ) ) {
      $error .= "The Functional Role's abbreviation you try to add already exists and can't be added therefore<BR>\n";
      $putintoaddrole = 1;
    }

    my $reacthtml = '';
    my $hopereacthtml = '';
    
    if ( $frreadd ) {
      $reacthtml = join( ", ", map { &HTML::reaction_link( $_ ) } split( ', ', $frreadd ) );
    }
    if ( $frhradd ) {
      $hopereacthtml = join( ", ", map { &HTML::reaction_link( $_ ) } split( ', ', $frhradd ) );
    }

    if ( $putintoaddrole ) {
      $addrolehash = { 'role' => $fradd,
		       'subset' => $subsetadd,
		       'abbr' => $frabadd,
		       'reaction' => $frreadd,
		       'reactionhtml' => $reacthtml,
		       'hopereaction' => $frhradd,
		       'hopereactionhtml' => $hopereacthtml,
		       'literatures' => $frpubs->{ $fradd },
		       'gos' => $frgo->{ $fradd } };
    }
    else {

      my $key = $frindexadd;
      if ( exists( $frshash->{ $key } ) ) {
	$key--;
	$key = $key.".$subkey";
	$subkey++;
      }
      
      my @subsetsadd = split( ', ', $subsetadd );
      $frshash->{ $key } = { 'role' => $fradd,
			     'subsets' => \@subsetsadd,
			     'abbr' => $frabadd,
			     'reaction' => $frreadd,
			     'reactionhtml' => $reacthtml,
			     'hopereaction' => $frhradd,
			     'hopereactionhtml' => $hopereacthtml,
			     'literatures' => $frpubs->{ $fradd },
			     'gos' => $frgo->{ $fradd } };

      $comment .= "Your functional role was added.<BR>\n";
    }
  }

  return ( $frshash, $different_react_hope, $addrolehash, $comment, $error );
}


#############################################################
# Construct a hash containing all info for functional roles #
# Point to edit backend functions if someone decides so :)  #
#############################################################
sub getFunctionalRoles {

  my ( $self, $name ) = @_;
  
  my $frshash;

  # constuct a subsystem object to access subsystem #
  my $subsystem = new Subsystem( $name, $self->{ 'fig' }, 0 );

  # get func. roles, reactions, hope reactions #
  my @roles = $subsystem->get_roles();
  my $reactions = $subsystem->get_reactions;
  my %hope_reactions = $subsystem->get_hope_reactions;
  my %hope_reaction_notes = $subsystem->get_hope_reaction_notes;
  my %hope_reaction_links = $subsystem->get_hope_reaction_links;
  my $frpubs = $self->getLiteratures( $name, \@roles );
  my $frgo = $self->getGOs( $name, \@roles );

  my $different_react_hope = 0;

  # extract data and put it into hash #
  foreach my $role ( @roles ) {

    my $index = $subsystem->get_role_index( $role );
    my $abbr  = $subsystem->get_role_abbr( $index );

    my $react;
    my $reacthtml;
    if ( defined( $reactions->{ $role } ) ) {
      $react = $reactions ? join( ", ", @{ $reactions->{ $role } } ) : "";
      $reacthtml = $reactions ? join( ", ", map { &HTML::reaction_link( $_ ) } @{ ( $reactions->{ $role } ) } ) : "";
    }

    if ( !defined( $react ) ) {
      $react = "";
      $reacthtml = "";
    }

    my $hope_react = $hope_reactions{ $role };
    my $hope_react_html = "";
    if ( defined( $hope_react ) ) {
      $hope_react = %hope_reactions ? join( ", ", @{ $hope_reactions{ $role } } ) : "";
      $hope_react_html = %hope_reactions ? join( ", ", map { &HTML::reaction_link( $_ ) } @{ ( $hope_reactions{ $role } ) } ) : "";
    }

    if ( !defined( $hope_react ) ) {
      $hope_react = "";
      $hope_react_html = "";
    }

    if ( $react ne $hope_react ) {
      $different_react_hope = 1;
    }

    # role name #
    $frshash->{ $index }->{ 'role' } = $role;
    # role abbreviation #
    $frshash->{ $index }->{ 'abbr' } = $abbr;
    # reactions string like "R00001, R00234" #
    $frshash->{ $index }->{ 'reaction' } = $react;
    # reactions string, but formated as html links to KEGG #
    $frshash->{ $index }->{ 'reactionhtml' } = $reacthtml;
    # reactions string like "R00001, R00234", now from Hope College #
    $frshash->{ $index }->{ 'hopereaction' } = $hope_react;
    # reactions string, but formated as html links to KEGG, Hope College #
    $frshash->{ $index }->{ 'hopereactionhtml' } = $hope_react_html;
    # Literature for functional role
    $frshash->{ $index }->{ 'literatures' } = $frpubs->{ $role };
    # Go Terms for functional role
    $frshash->{ $index }->{ 'gos' } = $frgo->{ $role };
    
  }

  ####################
  # data for subsets #
  ####################

  my @subsets = $subsystem->get_subset_namesC;

  foreach my $s ( @subsets ) {
    next if ( $s =~ /^[Aa]ll$/ );
    my @subsets2 = $subsystem->get_subsetC_roles( $s );
    foreach my $ss ( @subsets2 ) {
      my $roleindex = $subsystem->get_role_index( $ss );
      push @{ $frshash->{ $roleindex }->{ 'subsets' } }, $s;
    }
  }

  return ( $frshash, $different_react_hope );
}


############################
# get GO-string for roles  #
############################
sub getGOs {
  my ( $self, $name, $roles ) = @_;

  if ( !defined( $roles ) || scalar( @$roles ) == 0 ) {
    return {};
  }

  my @attroles;
  foreach my $role ( @$roles ) {
    my $attrole = "Role:$role";
    push @attroles, $attrole;
  }

  my $frgocounter;
  my $frgo = {};
  my @gonumbers = $self->{ 'fig' }->get_attributes( \@attroles, "GORole" );

  foreach my $k ( @gonumbers ) {
    my ( $role, $key, $value ) = @$k;
    if ( $role =~ /^Role:(.*)/ ) {
      push @{ $frgocounter->{ $1 } }, "<A HREF='http://amigo.geneontology.org/cgi-bin/amigo/go.cgi?view=details&search_constraint=terms&depth=0&query=".$value."' target=_blank>$value</A>";
    }
  }

  foreach my $role ( @$roles ) {
    my $gonumsforrole = $frgocounter->{ $role };
    if ( $gonumsforrole ) {
      my $joined = join ( ', ', @$gonumsforrole );
      $frgo->{ $role } = $joined;
    }
    else {
      $frgo->{ $role } = '-';
    }
  }
  return $frgo;
}


####################################
# get Literature-string for roles  #
####################################
sub getLiteratures {
  my ( $self, $name, $roles ) = @_;

  my $esc_name = uri_escape($name, "^A-Za-z0-9\-_.!~*()");

  my @attroles;
  foreach my $role ( @$roles ) {
    my $attrole = "Role:$role";
    push @attroles, $attrole;
  }

  my $frpubscounter;
  my $frpubs;
  my $fupubscounter;
  my @rel_lit_num = $self->{ 'fig' }->get_attributes( \@attroles, "ROLE_PUBMED_CURATED_RELEVANT" );
  my @und_lit_num = $self->{ 'fig' }->get_attributes( \@attroles, "ROLE_PUBMED_NOTCURATED" );

  foreach my $k ( @rel_lit_num ) {

    my ( $role, $key, $value ) = @$k;
    if ( $role =~ /^Role:(.*)/ ) {
      $frpubscounter->{ $1 }++;
    }
  }

  foreach my $k ( @und_lit_num ) {

    my ( $role, $key, $value ) = @$k;
    if ( $role =~ /^Role:(.*)/ ) {
      $fupubscounter->{ $1 }++;
    }
  }

  foreach my $role ( @$roles) {
    my $esc_role = uri_escape($role, "^A-Za-z0-9\-_.!~*()");

    if ( defined( $frpubscounter->{ $role } ) ) {
      $frpubs->{ $role } = '<a href="./seedviewer.cgi?page=DisplayRoleLiterature&subsys='.$esc_name.'&role='.$esc_role.'" target=_blank>'.$frpubscounter->{ $role }.' Pubs ';
    }
    else {
      $frpubs->{ $role } = '<a href="./seedviewer.cgi?page=DisplayRoleLiterature&subsys='.$esc_name.'&role='.$esc_role.'" target=_blank>0 Pubs ';
    }

    if ( defined( $fupubscounter->{ $role } ) ) {
      $frpubs->{ $role } .= '( '.$fupubscounter->{ $role }.' proposed )';
    }
    else {
      $frpubs->{ $role } .= '( 0 proposed )'
    }
    $frpubs->{ $role } .= '</a>';

  }

  return $frpubs;
}

