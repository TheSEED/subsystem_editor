package SubsystemEditor::WebPage::ShowSubsets;

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

  $self->application->register_component( 'Table', 'sstable'  );
  $self->application->register_component( 'Info', 'CommentInfo');

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
  my $name = $self->{ 'cgi' }->param( 'subsystem' );
  $self->{ 'name' } = $name;
  my $ssname = $name;

  my $esc_name = uri_escape( $name );

  $ssname =~ s/\_/ /g;

  # look if someone is logged in and can write the subsystem #
  $self->{ 'can_alter' } = 0;
  my $user = $self->application->session->user;

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

  if ( $user && $user->has_right( $self->application, 'edit', 'subsystem', $name ) ) {
    $self->{ 'can_alter' } = 1;
    $self->{ 'fig' }->set_user( $self->{ 'seeduser' } );
  }

  my $hiddenvalues = {};
  my $build_subsets_string = '';

  $self->{ 'subsystem' } = new Subsystem( $name, $self->{ 'fig' }, 0 );

  my ( $error, $comment ) = ( "", "" );
  my $bsshash;

  #########
  # Tasks #
  #########

  if ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'CreateSubset' ) {
    my $newSubsetName = $self->{ 'cgi' }->param( 'subsetname' );
    $build_subsets_string = $self->{ 'cgi' }->param( 'build_subsets_string' );

    if ( defined( $build_subsets_string ) && $build_subsets_string ne '' ) {
      $build_subsets_string =~ s/\r//g;
      chomp $build_subsets_string;
      $build_subsets_string .= "\n";
    }

    my $formerbsshash = $self->get_bss_info( $build_subsets_string, 0 );
    
    if ( !defined( $newSubsetName ) || $newSubsetName eq '' ) {
      $error .= "No Subset Name given for your new Subset, please specify a unique name<BR>";
    }
    elsif ( defined( $formerbsshash->{ $newSubsetName } ) ) {
      $error .= "This subset already exists. Please delete it first if you want to edit it<BR>";
    }
    else {
      my @whichs = $self->{ 'cgi' }->param( "rolesCreateSubset" );
      
      foreach my $ws ( @whichs ) {
	$build_subsets_string .= $newSubsetName;
	$ws =~ /role(##-##.*)/;
	my $this = $1;
	$this =~ s/\r//g;
	$build_subsets_string .= $this;
	$build_subsets_string .= "\n";
      }
    }
    $bsshash = $self->get_bss_info( $build_subsets_string, 0 );
    
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) =~ /^DeleteSubset/ ) {
    $build_subsets_string = $self->{ 'cgi' }->param( 'build_subsets_string' );
    $build_subsets_string =~ s/\r//g;

    my $deletewhich = $self->{ 'cgi' }->param( 'buttonpressed' );
    $deletewhich =~ /DeleteSubset\_(.*)/;
    my $subset_to_delete = $1;
    
    if ( $subset_to_delete && $subset_to_delete ne '' ) {
      my @bsss = split( "\n", $build_subsets_string );
      $build_subsets_string = '';
      foreach my $line ( @bsss ) {
	next if ( !defined( $line ) || $line eq '' || $line =~ /^##-##/ );
	unless ( $line =~ /^$subset_to_delete/ ) {
	  $build_subsets_string .= $line."\n";
	}
      }
    }
    $bsshash = $self->get_bss_info( $build_subsets_string, 0 );
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'SaveSubsets' ) {
    $build_subsets_string = $self->{ 'cgi' }->param( 'build_subsets_string' );
    $build_subsets_string =~ s/\r//g;
    
    $bsshash = $self->get_bss_info( $build_subsets_string, 0 );
    my $subsets;
    my $view;
    my $memin;

    # delete old subsetes
    foreach my $s ( $self->{ 'subsystem' }->get_subset_namesC ) {
      next if ( $s eq "All" );
      $self->{ 'subsystem' }->delete_subsetC( $s );
    }
    
    # put in subsets #
    foreach my $ssarrk ( keys %$bsshash ) {
      my @rolelist;
      foreach my $l ( @{ $bsshash->{ $ssarrk }->{ 'members' } } ) {
	push @rolelist, $self->{ 'subsystem' }->get_role_from_abbr( $l );
      }
      $self->{ 'subsystem' }->set_subsetC( $ssarrk, \@rolelist );
    }
    
    
    $self->{ 'subsystem' }->write_subsystem();
    $comment = "Saved subsets successfully<BR>";
  }
  else {
    $build_subsets_string = $self->get_subsets_from_subsystem();
    $bsshash = $self->get_bss_info( $build_subsets_string, 1 );
  }

  ############################
  # Build HTML Elements here #
  ############################

  ## Subsets table ##
  my $success = $self->subsets_table( $bsshash );

  my $subsetstable = $self->application->component( 'sstable' );

  my $bss = $build_subsets_string || '';


  ## Choose subsets ##
  my $choose_subsets = $self->choose_subsets( $build_subsets_string );

  ## Save Button ##
  my $donesubsets = "<INPUT TYPE=BUTTON VALUE='Save Editing to Subsets' ONCLICK='SubmitNewMeta( \"SaveSubsets\", \"a\" );'>";

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


  $hiddenvalues->{ 'build_subsets_string' } = $build_subsets_string;
  $hiddenvalues->{ 'buttonpressed' } = 'none';
  $hiddenvalues->{ 'subsystem' } = $name;

  ###########
  # Content #
  ###########
  
  if ( !$self->{ 'can_alter' } ) {
    my $content = "<H1>Subsets for $ssname</H1>";
    $content .= "You do not have the right to edit the subsets of this metagenome";
    return $content;
  }

  my $content = "<H1>Subsets for $ssname</H1>";


  ####################
  # Display comments #
  ####################
  if ( defined( $comment ) && $comment ne '' ) {
    my $info_component = $self->application->component( 'CommentInfo' );
    
    $info_component->content( $comment );
    $info_component->default( 0 );
    $content .= $info_component->output();
  } 
  if ( defined( $error ) && $error ne '' ) {
    $self->application->add_message( 'warning', $error );
  }

  $content .= $self->start_form( 'form', $hiddenvalues );
  $content .= $subsetstable->output();

  $content .= "<BR>".$donesubsets."<BR><BR>\n";
  
  $content .= "<DIV Style=\"border:2px solid black; padding:10px;\">\n";
  $content .= $choose_subsets;
  $content .= "</DIV>\n";

  $content .= $self->end_form();

  return $content;
}



sub choose_subsets {

  my ( $self ) = @_;

  my $panel = '<H3>Subset Name</H3>';
  my $textfield = "<INPUT TYPE=TEXT NAME=\"subsetname\" SIZE=10>";
  my $textbutton = "<INPUT TYPE=BUTTON VALUE='Create Subset' ONCLICK='SubmitNewMeta( \"CreateSubset\", \"a\" );'>";
  $panel .= "<TABLE><TD><B>Subset Name:</B></TD><TD>$textfield</TD></TABLE>";
  $panel .= "<H3>Choose members of the subset</H3>";
  $panel .= "<P>Check the functional roles that should be the members of the subset and press \'Create Subset\' to finish.</P>";

  my @createtables;

  my $sshandle = $self->{ 'subsystem' };
  my @roles = $sshandle->get_roles();

  # construct subsets create table #
  my $createtable .= "<TABLE>";
  my $checkline = '';
  my $thline = '';
  my $combline = '';
  
  my $counter = 0;
  foreach my $r ( @roles ) {
    $counter++;
    my $abb = $sshandle->get_abbr_for_role( $r );
    $thline .= "<TH>$abb</TH>";
    
    my $role_checkbox = $self->{ 'cgi' }->checkbox( -name     => "rolesCreateSubset",
						    -id       => "role##-##$abb",
						    -value    => "role##-##$abb",
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


  $panel .= "<TABLE>";
  foreach my $ct ( @createtables ) {
    $panel .= "<TR><TD>$ct</TD></TR>";
  }

  $panel .= "<TR><TD>$textbutton</TD></TR>";
  $panel .= "</TABLE>";
  return $panel;

}

sub subsets_table {
  
  my ( $self, $bsshash ) = @_;

  my $subsets_table = $self->application->component( 'sstable' );

  $subsets_table->columns( [ 'Name', 'Members', 'Delete' ] );

  my @allsets = keys %$bsshash;
  my $sstdata = [];
  foreach my $set ( @allsets ) {

    my $show_checked = $bsshash->{ $set }->{ 'visible' } || 0;
    my $collapse_checked = $bsshash->{ $set }->{ 'collapsed' } || 0;

    my $mems = $bsshash->{ $set }->{ 'members' };
    my @nicemems;
    my @nicesubsystems;
    foreach ( @$mems ) {
      $self->{ 'in_subset_role' }->{ $_ } = 1;
      push @nicemems, $_;
    }
  
    my $button_subset = "<INPUT TYPE=BUTTON VALUE='Delete' ONCLICK='SubmitNewMeta( \"DeleteSubset_$set\", \"a\" );'>";
    my $row = [ $set, join( ', ', @nicemems ), $button_subset ];
    
    push @$sstdata, $row;
  }
  $subsets_table->data( $sstdata );
}

sub get_subsets_from_subsystem {
  my ( $self ) = @_;
  
  my $build_subsets_string = '';

  my @subsets = $self->{ 'subsystem' }->get_subset_namesC;

  foreach my $s ( @subsets ) {
    next if ( $s =~ /^[Aa]ll$/ );
    my @subsets2 = $self->{ 'subsystem' }->get_subsetC_roles( $s );
    foreach my $ss ( @subsets2 ) {
      my $abbr = $self->{ 'subsystem' }->get_abbr_for_role( $ss );
      $build_subsets_string .= $s.'##-##'.$abbr."\n";
    }
  }

  return $build_subsets_string;
}


sub get_bss_info {
  my ( $self, $build_subsets_string, $fromfile ) = @_;
  
  my $bsshash;
  my $showhash;
  my $colhash;
  
  my @stuff = split( "\n", $build_subsets_string );
  foreach my $s ( @stuff ) {
    my ( $ssname, $abb, $visible, $collapsed ) = split( "##-##", $s );
    push @{ $bsshash->{ $ssname }->{ 'members' } }, $abb;
    if ( $fromfile ) {
      $bsshash->{ $ssname }->{ 'visible' } = $visible;
      $bsshash->{ $ssname }->{ 'collapsed' } = $collapsed;
    }
    else {
      $bsshash->{ $ssname }->{ 'visible' } = $showhash->{ $ssname } || 0;
      $bsshash->{ $ssname }->{ 'collapsed' } = $colhash->{ $ssname } || 0;
    }
  }
  return $bsshash;
}
