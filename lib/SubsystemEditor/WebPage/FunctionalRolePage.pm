package SubsystemEditor::WebPage::FunctionalRolePage;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;

use FIG;
use FIGV;
use UnvSubsys;
use FFs;

use base qw( WebPage );

1;

##################################################
# Method for registering components etc. for the #
# application                                    #
##################################################
sub init {
  my ( $self ) = @_;

  $self->application->register_component('Table', 'FunctionalRoleTable');
  $self->application->register_component('Table', 'SubsystemsTable');
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

  my $application = $self->application();
  $self->{ 'cgi' } = $application->cgi();
  $self->{ 'fig' } = new FIG();

  # look if someone is logged in and can write the subsystem #
  my $can_alter = 0;
  my $user = $application->session->user;

  my $dbmaster = $self->application->dbmaster;
  my $ppoapplication = $self->application->backend;
  
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

  if ( $user ) {
#    if ( $user->has_right( $self->application, 'edit', 'subsystem', $name ) ) {
      $can_alter = 1;
      $self->{ 'fig' }->set_user( $self->{ 'seeduser' } );
#    }
  }

  $self->title( "Functional Role Page" );

  # first, get the role and look if it is defined,
  # if not, show error message.
  my $role = $self->{ 'cgi' }->param( 'fr' );
  my $unescrole = uri_unescape( $role );
  $role = $unescrole;
#  $role =~ s/_/ /g;
  unless ( defined( $unescrole ) ) {
    $application->add_message('warning', 'you need to supply a role');
    return "";
  }

  my $hiddenvalues;

  #########
  # TASKS #
  #########
  
  my $comment = '';
  my $error = '';

  # Do we want a different role?

  if ( defined( $self->{ 'cgi' }->param( 'SUBMITSEARCHROLE' ) ) ) {
    my $searchrole = $self->{ 'cgi' }->param( 'SEARCHROLE' );
    if ( defined( $searchrole ) && $searchrole ne '' ) {
      $role = $searchrole;
    }
  }

  # Do we want to rename the role?

  elsif ( defined( $self->{ 'cgi' }->param( 'SUBMITNEWROLE' ) ) && $self->{ 'cgi' }->param( 'SUBMITNEWROLE' ) != 0 ) {
    # print STDERR "HALLO1\n";

    my $newname = $self->{ 'cgi' }->param( 'NEWROLE' );
    if ( !defined( $newname ) || $newname eq '' ) {
      $newname = $self->{ 'cgi' }->param( 'NEWROLEFORCE' );
    }

    #  Check that we have data for a rename

    if ( defined( $newname ) && $newname ne '' ) {
      # print STDERR "HALLO2\n";
 
      # Is there a "conflict" without an override?

      my $override = $self->{ 'cgi' }->param( 'override' );
      # $newname =~ s/_/ /g;    # removed by GJO, 2012-12-08
      my ( $discard, $ssnames, $pegs ) = $override ? ( 0, [], [] ) : $self->checkrole( $newname );

      if ( $discard && ( !defined( $override ) || $override == 0 ) ) {
        # print STDERR "HALLO3\n";
        $error .= "<B>The change of function could not be applied due to the following error(s):</B><BR><BR>\n";

        if ( scalar( @$ssnames > 0 ) ) {
          $error .= "The new role name is a functional role in the following subsystems:<BR>\n";
          foreach ( @$ssnames ) {
            $error .= "- <A HREF='SubsysEditor.cgi?page=ShowSubsystem&subsystem=$_' target=_blank>$_</A><BR>\n";
          }
        }

        if ( scalar( @$pegs > 0 ) ) {
          $error .= "There are the following pegs that are already annotated with this role:<BR>\n";
          foreach ( @$pegs ) {
            # $error .= "- <A HREF='./protein.cgi?prot=$_&user=".$self->{ 'seeduser' }."\&new_framework=0' target=_blank>$_</A><BR>\n";
            $error .= "- <A HREF='./seedviewer.cgi?page=Annotation&feature=$_&user=".$self->{ 'seeduser' }."' target=_blank>$_</A><BR>\n";
          }
        }

        # Build the "Force Change Role" (i.e., override) button

        $hiddenvalues->{ 'override' } = 1;
        $hiddenvalues->{ 'NEWROLEFORCE' } = $newname;
        $error .= "<INPUT TYPE=BUTTON VALUE='Force Change Role' NAME='SUBMITNEWROLEBUTTON' ID='SUBMITNEWROLEBUTTON' ONCLICK='if ( confirm( \"Do you really want to change the function of all matching roles in subsystems and all matching annotations of CDSs although there exist already pegs with that annotation?\" ) ) { 
 document.getElementById( \"SUBMITNEWROLE\" ).value = 1;
 document.getElementById( \"functionalrole\" ).submit(); }'>";
        $error .= "<BR>\n";
      }

      # No problems, or there is an override, so do the rename

      elsif ( $role ne $newname ) {
        my ( $putcomment, $puterror ) = $self->{ 'fig' }->change_funcrole( $role, $newname, $self->{ 'seeduser' } );
        $error .= $puterror;
        $comment .= $putcomment;
        $role = $newname;
      }
    }
  }
    
  #########################
  # get some data we need #
  #########################
  
  # retrieve all cds with this role
  my @pegs = $self->{ 'fig' }->seqs_with_role( $role );

  # ec number for this role #
  my $ec_number = "No EC number recorded";
  if ( $role =~ /EC\s([0-9\-\.a-z]+)/i ) {
    $ec_number = $1;
    $ec_number = "<A HREF='http://www.genome.jp/dbget-bin/www_bget?ec:$ec_number' target='outbound'>" . $ec_number . "</A>";
  }

  # go number for this role #
  my $go_numbers = $self->getGO( $role );

  # literature for this role #
  my $literature = $self->getLiterature( $role );

  # calculate some statistics on the members
  my $orgs;
  foreach my $peg ( @pegs ) {
    $peg =~ /fig\|(\d+\.\d+)\.peg\.\d+/;
    push( @{ $orgs->{ $1 } }, $peg );
  }
  my $domains;
  foreach my $org (keys(%$orgs)) {
    my $dom = $self->{ 'fig' }->genome_domain( $org );
    if ( exists( $domains->{ $dom } ) ) {
      $domains->{ $dom }++;
    } 
    else {
      $domains->{ $dom } = 1;
    }
  }

  # subsystems for this role #
  my @subsystems = $self->{ 'fig' }->function_to_subsystems( $role );
  my @subsystemrows;
  my %subsystems_to_number;
  my $counter = 0;

  foreach my $ssn ( @subsystems ) {
    $counter++;
    $subsystems_to_number{ $ssn } = $counter;
    my $ss = new Subsystem( $ssn, $self->{ 'fig' }, 0 );
    if ( !defined( $ss ) ) {
      print STDERR "Could not get Subsystem Object for $ssn\n";
      next;
    }

    # look if the role is just auxilliary in that subsystem
    my $isauxrole = $self->{ 'fig' }->is_aux_role_in_subsystem( $ssn, $role );
    my $isauxroleword = 'no';
    if ( $isauxrole ) {
      $isauxroleword = 'yes';
    }

    # get the reactions for that role curated in that subsystem
    my $reactions = $ss->get_reactions;
    my $hope_reactions = $ss->get_hope_reactions;
    my $reacthtml = "";
    if ( defined( $reactions->{ $role } ) ) {
      $reacthtml = $reactions ? join( ", ", map { &HTML::reaction_link( $_ ) } @{ ( $reactions->{ $role } ) } ) : "";
    }
    my $hope_react_html = "";
    if ( ref $hope_reactions && defined( $hope_reactions->{ $role } ) ) {
      $hope_react_html = join( ", ", map { &HTML::reaction_link( $_ ) } @{ ( $hope_reactions->{ $role } ) } );
    }
    
    my $r = [ "<A HREF='SubsysEditor.cgi?page=ShowSubsystem&subsystem=$ssn' target=_blank>$ssn</A><BR>\n", $ss->get_curator, $isauxroleword, $reacthtml, $hope_react_html ];
    push @subsystemrows, $r;
  }

  # FigFams
  my $figfamsObject = new FFs( $self->{fig}->get_figfams_data(), $self->{ 'fig' } );
  my @fams = $figfamsObject->families_implementing_role( $role );

  # change role to
  my $textfield = "<INPUT TYPE=TEXT NAME='NEWROLE' ID='NEWROLE' STYLE='width: 700px;'>";
  my $changerolebutton = "<INPUT TYPE=HIDDEN NAME='SUBMITNEWROLE' ID='SUBMITNEWROLE' VALUE=0><INPUT TYPE=BUTTON VALUE='Change Role' NAME='SUBMITNEWROLEBUTTON' ID='SUBMITNEWROLEBUTTON' ONCLICK='if ( confirm( \"Do you really want to change the function of all matching roles in subsystems and all matching annotations of CDSs?\" ) ) { 
 document.getElementById( \"SUBMITNEWROLE\" ).value = 1;
 document.getElementById( \"functionalrole\" ).submit(); }'>";

  # search role
  my $searchfield = "<INPUT TYPE=TEXT NAME='SEARCHROLE' ID='SEARCHROLE' STYLE='width: 700px;'>";
  my $searchbutton = "<INPUT TYPE=SUBMIT NAME='SUBMITSEARCHROLE' ID='SUBMITSEARCHROLE' VALUE='Show this Role'>";


  #################################
  # construct the html parts here #
  #################################

  # search for functional role table
  my $searchroletable = "<H2>Search for another functional role</H2>";
  $searchroletable .= "<TABLE>\n";
  $searchroletable .= "<TR><TD>$searchfield</TD></TR>\n";
  $searchroletable .= "<TR><TD>$searchbutton</TD></TR>\n";
  $searchroletable .= "</TABLE>\n";

  # change role table
  my $changeroletable = "<H2>Change Functional Role</H2>";
  $changeroletable .= "<TABLE>\n";
  $changeroletable .= "<TR><TD>Be careful! This will change the role name in all subsystems and all pegs that do or do not belong to subsystems.<TD></TR>\n";
  $changeroletable .= "<TR><TD><B>Change Role for all Genes and Subsystems To:</B></TD></TR>\n";
  $changeroletable .= "<TR><TD>$textfield</TD></TR>\n";
  $changeroletable .= "<TR><TD>$changerolebutton</TD><TR>\n";
  $changeroletable .= "</TABLE>";

  # infotable 
  my $infotable = "<TABLE>\n";
  $infotable .= "<TR><TH>EC number</TH><TD>$ec_number</TD></TR>\n";
  $infotable .= "<TR><TH>GO numbers</TH><TD>$go_numbers</TD></TR>\n";
  $infotable .= "<TR><TH>Literature</TH><TD>$literature</TD></TR>\n";
  $infotable .= "</TABLE>\n";

  # subsystems table
  my $sstable = $application->component( 'SubsystemsTable' );
  my $sstable_columns = [ { name => 'Name', sortable => 1 }, 
			  { name => 'Curator', sortable => 1 }, 
			  { name => 'Aux.' },
			  { name => 'Reactions' },
			  { name => 'Hope Reactions' }
			];
  $sstable->columns( $sstable_columns );
  $sstable->data( \@subsystemrows );

  # get members
  my $table_data = [];
  my $table_hover_data = [];
  foreach my $peg (@pegs) {
    my $org = '-';
    if ($peg =~ /fig\|(\d+\.\d+)/) {
      $org = $1;
    }
    else {
      next;
    }
    my $org_name = $self->{ 'fig' }->org_of($peg) || "-";
    my ($genus, $domain) = $self->{ 'fig' }->genus_species_domain($org);

    my $ssforpeg;
    my $ssforpeg_hover;
    my @nums;
    my @hovers;
    my @subsystems_for_peg = $self->{ 'fig' }->peg_to_subsystems( $peg );
    foreach my $ssfp ( @subsystems_for_peg ) {
      if ( !defined( $subsystems_to_number{ $ssfp } ) ) {
	$counter++;
	$subsystems_to_number{ $ssfp } = $counter;
      }
      push @nums, $subsystems_to_number{ $ssfp };
      push @hovers, $ssfp;
    }

    my $peglink = $self->fid_link( $peg );
    $peglink = "<A HREF='$peglink' target=_blank>$peg</A>";

    my @dlits = map {
	my $pmid = $_->[2];
	"<a target='_blank' href='http://www.ncbi.nlm.nih.gov/pubmed/?term=$pmid'>$pmid</a>" }
    	grep { $_->[0] eq 'D' } $self->{fig}->get_dlits_for_peg($peg);
    
    push( @$table_data,
	 [ "$peglink",
	  "<span style='display:none;'>$org_name</span><a href='seedviewer.cgi?page=Organism&organism=$org' target=_blank>$org_name</a>",
	  $domain,
          { data => join( ', ', @nums ), tooltip => join( ', ', @hovers ) },
	  join(" ", @dlits)
	  ] );
  }
  my @sorted_data = sort { $a->[1] cmp $b->[1] } @$table_data;
  
  # calculate statistics
  my $statistics = "<table><TR><TD COLSPAN=2><H2>This role occurs in these organisms:</H2></TD></TR>";
  $statistics .= "<tr><th>Number of Occurrences</th><td>" . scalar(@$table_data) . "</td></tr><tr><th>Number of Organisms</th><td>" . scalar(keys(%$orgs)) . "</td></tr>";
  
  my $archaeal = $domains->{'Archaea'} || 0;
  my $bacterial = $domains->{'Bacteria'} || 0;
  my $eukaryal = $domains->{'Eukaryota'} || 0;
  my $viral = $domains->{'Virus'} || 0;
  
  $statistics .= "<tr><th> &raquo Archaea</th><td>" . $archaeal . "</td></tr>";
  $statistics .= "<tr><th> &raquo Bacteria</th><td>" . $bacterial . "</td></tr>";
  $statistics .= "<tr><th> &raquo Eukaryota</th><td>" . $eukaryal . "</td></tr>";
  $statistics .= "<tr><th> &raquo Virus</th><td>" . $viral . "</td></tr>";
  $statistics .= "</table>";

  # Alignments and trees with role

  my $aligns_and_trees = '';
  if ( eval { require AlignsAndTreesServer; } )
  {
    my @alignID_count = AlignsAndTreesServer::aligns_with_role( $self->{ 'fig' }, $role );
    if ( @alignID_count )
    {
      my $seeduser = $self->{ 'seeduser' } || $self->{ cgi }->param( 'user' ) || '';
      my @lines;
      push @lines, "<TABLE>\n";
      push @lines, "  <TR><TD ColSpan=3><H2>Alignments and trees with this role:</H2></TD></TR>\n";
      push @lines, "  <TR><TD Align=right><B>Occurances of role</B></TD><TD Align=center><B>Alignment</B></TD><TD Align=center><B>Tree</B></TD></TR>\n";

      foreach ( @alignID_count )
      {
        my ( $id, $count ) = @$_;
        my $align_link = qq(<A HRef="seedviewer.cgi?page=AlignTreeViewer&user=$seeduser&align_id=$id" Target=_blank>$id</A>);
        my $tree_link  = qq(<A HRef="seedviewer.cgi?page=AlignTreeViewer&user=$seeduser&tree_id=$id" Target=_blank>$id</A>);
        push @lines, "  <TR><TH Align=right>$count</TH><TD Align=center>$align_link</TD><TD Align=center>$tree_link</TD></TR>\n";
      }

      push @lines, "<TABLE>\n";

      $aligns_and_trees = join( '', @lines );
    }
  }

  my $functional_role_table = $application->component('FunctionalRoleTable');
  $functional_role_table->columns( [ { name => 'ID', sortable => 1, filter => 1 },  
				     { name => 'Organism', filter => 1, sortable => 1 }, 
				     { sortable => 1, name => 'Domain', filter => 1, operator => 'combobox' },
				     { name => 'Subsystems', sortable => 1, filter => 1 },
				     { name => 'Literature', filter => 1, sortable => 1 } ] );

  $functional_role_table->show_export_button(1);
  $functional_role_table->items_per_page(15);
  $functional_role_table->show_select_items_per_page(1);
  $functional_role_table->show_top_browse(1);
  $functional_role_table->show_bottom_browse(1);
  $functional_role_table->data(\@sorted_data);
  $functional_role_table->width(800);


   my $figfamsinfo = "<TABLE><TR><TH>Figfams for this role:</TH>";
   my $first = 1;
   if ( scalar( @fams ) > 0 ) {
     foreach my $fam ( @fams ) {
       if ( $first ) {
 	$figfamsinfo .= "<TD><a href='seedviewer.cgi?page=FigFamViewer&figfam=$fam' target='_blank'>$fam</a></TD></TR>";
 	$first = 0;
       }
       else {
 	$figfamsinfo .= "<TR><TD></TD><TD><a href='seedviewer.cgi?page=FigFamViewer&figfam=$fam' target='_blank'>$fam</a></TD></TR>";
       }
     }
   }
  else {
     $figfamsinfo .= "<TD>No FigFam found</TD></TR>";
   }
   $figfamsinfo .= "</TABLE>";

  #############################
  # put content together here #
  #############################


  my $content = "<H1>Functional role page for $role</H2>";

  $hiddenvalues->{ 'fr' } = $role;
  $content .= $self->start_form( 'functionalrole', $hiddenvalues );

  # display comments #
  if ( defined( $comment ) && $comment ne '' ) {
    my $info_component = $application->component( 'CommentInfo' );

    $info_component->content( $comment );
    $info_component->default( 0 );
    $content .= $info_component->output();
  }    

  $content .= "<TABLE><TR><TD>$infotable</TD><TD style='padding-left: 70px'><DIV style=\"border-color: black; border-style: solid; border-width: thin; padding: 10px\">$searchroletable</DIV></TD></TR></TABLE>";;
  $content .= "<H2>This functional role is member of the following subsystems:</H2>\n";
  $content .= $sstable->output();
  if ( !$can_alter ) {
    $content .= $statistics;
  }
  else {
    $content .= "<TABLE><TR><TD>$statistics</TD><TD style='padding: 20px'><DIV style=\"border-color: black; border-style: solid; border-width: thin; padding: 10px\">$changeroletable</DIV></TD></TR></TABLE>";
  }
  $content .= $aligns_and_trees;
  $content .= "<H2>This functional role is implemented by the following FigFams:</H2>\n";
  $content .= $figfamsinfo;
  $content .= "<H2>The following pegs are annotated with this functional role:</H2>\n";
  $content .= $functional_role_table->output();

  $content .= $self->end_form();

  ###############################
  # Display errors and comments #
  ###############################
 
  if ( defined( $error ) && $error ne '' ) {
    $self->application->add_message( 'warning', $error );
  }

  return $content;
  
}

###########################
# get GO-string for role  #
###########################
sub getGO {
  my ( $self, $role ) = @_;

  my $attrole = "Role:$role";

  my $frgocounter;
  my @gonumbers = $self->{ 'fig' }->get_attributes( [ $attrole ], "GORole" );

  foreach my $k ( @gonumbers ) {
    my ( $role, $key, $value ) = @$k;
    if ( $role =~ /^Role:(.*)/ ) {
      push @{ $frgocounter->{ $1 } }, "<A HREF='http://amigo.geneontology.org/cgi-bin/amigo/go.cgi?view=details&search_constraint=terms&depth=0&query=".$value."' target=_blank>$value</A>";
    }
  }

  my $gonumsforrole = $frgocounter->{ $role };
  if ( $gonumsforrole ) {
    my $joined = join ( ', ', @$gonumsforrole );
    return $joined;
  }

  return "No GO number recorded";
}

####################################
# get Literature-string for roles  #
####################################
sub getLiterature {
  my ( $self, $role ) = @_;

  my $name = '';

  my $attrole = "Role:$role";
  my @attroles = ( $attrole );

  my $frpubscounter = 0;
  my $frpubs;
  my @rel_lit_num = $self->{ 'fig' }->get_attributes( \@attroles, "ROLE_PUBMED_CURATED_RELEVANT" );
  if ( !@rel_lit_num ) {
    return '0 Publications';
  }

  my $k = $rel_lit_num[ 0 ];

  my ( $r, $key, $value ) = @$k;
  if ( $r =~ /^Role:(.*)/ ) {
    $frpubscounter++;
  }

  if ( $frpubscounter > 0 ) {
    my $string = $frpubscounter.' Publication';
    if ( $frpubscounter > 1 ) {
      $string .= 's';
    }
    return $string;
  }
  return '0 Publications';
}


#############################################################
# This function checks if a role is already appearing in    #
# a subsystem or as the annotation of a peg. If so, it will #
# be discarded, as a renaming would maybe screw subsystems. #
#############################################################
sub checkrole {
  my ( $self, $newname ) = @_;

  # give all subsystems that include a gene with the new function
  my @ssnames = $self->{ 'fig' }->function_to_subsystems( $newname );

  # give all pegs that have the new function
  my @pegs = $self->{ 'fig' }->seqs_with_role( $newname, "master" );

  my $discard = 0;

  # if one is true, discard the renaming
  if ( scalar( @ssnames ) > 0 || ( scalar( @pegs ) > 0 ) ) {
    $discard = 1;
  }

  return ( $discard, \@ssnames, \@pegs );
}

sub fid_link {
    my ( $self, $fid ) = @_;
    my $n;

    if ($fid =~ /^fig\|\d+\.\d+\.([a-zA-Z]+)\.(\d+)/) {
      if ( $1 eq "peg" ) {
	  $n = $2;
	}
      else {
	  $n = "$1.$2";
	}
    }

#    return qq~./protein.cgi?prot=$fid&user=~.$self->{ 'seeduser' }.qq~\&new_framework=0~;
    return qq~./seedviewer.cgi?page=Annotation&feature=$fid&user=~.$self->{ 'seeduser' };
}
