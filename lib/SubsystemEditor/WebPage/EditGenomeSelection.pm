package SubsystemEditor::WebPage::EditGenomeSelection;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;
use GenomeLists;

use FIG;

use base qw( WebPage );

1;

##############################################################
# Method for registering components etc. for the application #
##############################################################
sub init {
  my ( $self ) = @_;

  $self->application->register_component(  'Table', 'sstable'  );
}

###############################
# Javascript for some buttons #
###############################
sub require_javascript {

  return [ './Html/showfunctionalroles.js' ];

}

##############################################
# Website content is returned by this method #
##############################################
sub output {
  my ( $self ) = @_;

  my $can_alter = 1;
  
  my $fig = new FIG;
  my $cgi = $self->application->cgi;


  # look if someone is logged in and can write #
  my $user = $self->application->session->user;

  my $dbmaster = $self->application->dbmaster;
  my $ppoapplication = $self->application->backend;
  

  ############################################
  ### GET PREFERENCES FOR AN EXISTING USER ###
  my $preferences = {};

  if ( defined( $user ) && ref( $user ) ) {
    my $pre = $self->application->dbmaster->Preferences->get_objects( { user        => $user,
									application => $ppoapplication } );
    %{ $preferences } = map { $_->name => $_ } @$pre;
  }
  ############################################

  # get a seeduser #
  my $seeduser = '';

  $can_alter = 0;
  if ( defined( $preferences->{ 'SeedUser' } ) ) {
    $seeduser = $preferences->{ 'SeedUser' }->value;
  }
  if ( $user ) {
    $can_alter = 1;
    $fig->set_user( $seeduser );
  }

  
  my $genomes = $cgi->param( 'genomes' );
  my $showlist = $cgi->param( 'showlist' );

  ######################
  # Construct the menu #
  ######################

  my $menu = $self->application->menu();

  ###############################
  # Get Existing Subsystem Data #
  ###############################

  my $gs = parse_genomes( $genomes );
  my $gs_genusspecies = get_genome_genus_species( $fig, $gs );
  my $description = '';
  my $listname = '';

  my ( $comment, $error );

  ###########
  # Actions #
  ###########

  if ( defined( $cgi->param( 'actionhidden' ) )  && $cgi->param( 'actionhidden' ) eq 'SHOWLIST' ) {
    $showlist = $cgi->param( 'namelist' );
  }
  elsif ( defined( $cgi->param( 'actionhidden' ) )  && $cgi->param( 'actionhidden' ) eq 'SAVE' ) {
    my $glhash;
    
    my $name = $cgi->param( 'LISTINPUT' );
    if ( !defined( $name ) || ( $name eq '' ) || ( $name eq 'New' ) ) {
      $showlist = '';
      $error .= "Could not save list, name is empty or invalid\n";
    }
    else {
      $name =~ s/ /_/g;
      $name = $seeduser . "_" . $name;
      $glhash->{ 'name' } = $name;
      $glhash->{ 'description' } = $cgi->param( 'DESC' );
      my @paramglist = $cgi->param( 'glist' );
      my @thesegenomes;
      foreach my $g ( @paramglist ) {
	if ( $g =~ /\( (\d+\.\d+) \)/ ) {
	  push @thesegenomes, $1;
	}
      }
      
      $glhash->{ 'genomes' } = \@thesegenomes;
      
      # ask here before creating if this one already exists
      my $gli = new GenomeLists( $glhash );
      my $succ = $gli->save();
      
      if ( $succ ) {
	$comment = "Sucessfully saved the GenomeList $name\n";
	$showlist = $name;
      }
      else {
	$error .= "Could not save GenomeList $name\n";
	$showlist = '';
      }
    }
  }

  ############################
  # get genome list for user #
  ############################

  my $genomeListsUser = get_genome_lists( $seeduser );
  my $gludefault = '';
  if ( defined( $genomes ) ) {
    unshift @{ $genomeListsUser }, 'New';
    $gludefault = 'New';
  }

  #####################
  # Get Showlist data #
  #####################

  if ( defined( $showlist ) ) {
    if ( $showlist eq '' ) {
      $gludefault = $cgi->param( 'namelist' );
      $description = $cgi->param( 'DESC' );
      $listname = $cgi->param( 'LISTINPUT' );
      my @showgenomes = $cgi->param( 'glist' );
      $gs_genusspecies = \@showgenomes;
    }
    else {
      my $GLObject = GenomeLists::load( $showlist );
      if ( $GLObject == -1 ) {
	my $showlist_user = $seeduser."_".$showlist;
	$GLObject = GenomeLists::load( $showlist_user );
      }
      if ( $GLObject == -1 ) {
	$error = "Could not load GenomeList $showlist\n";
      }
      else {
	$gludefault = $showlist;
	my $thisname;
	if ( $showlist =~ /$seeduser\_(.*)/ ) {
	  $thisname = $1;
	}
	else {
	  $thisname = $showlist;
	}
#	$gludefault = $thisname;
	$description = $GLObject->{ 'description' };
	$listname = $thisname;
	$gs_genusspecies = get_genome_genus_species( $fig, $GLObject->{ 'genomes' } );
      }
    }
  }

  # Genome Select... #
  my @taxids = $fig->genomes( 1 );
  my $gtochoosearr = get_genome_genus_species( $fig, \@taxids );
  my %gtochoose = map { $_ => 1 } @$gtochoosearr;
  foreach my $k ( @$gs_genusspecies ) {
    delete $gtochoose{ $k };
  }
  my @genomestochoosefrom = sort keys %gtochoose;

  ##############################
  # Construct the page content #
  ##############################

  my $namelist = $cgi->scrolling_list( -name => 'namelist',
				       -id   => 'namelist',
				       -values => $genomeListsUser,
				       -default => $gludefault,
				       -size => 8,				       
#				       -onclick => "putInText()"
				     );

  my $glist = $cgi->scrolling_list( -name => 'glist',
				    -id  => 'glist',
				    -multiple => 1,
				    -values => $gs_genusspecies,
				    -default => '',
				    -size => 5
				  );

  my $glisttochoose = $cgi->scrolling_list( -name => 'glisttochoose',
					    -id  => 'glisttochoose',
					    -multiple => 1,
					    -values => \@genomestochoosefrom,
					    -default => '',
					    -size => 5
					  );

  my $desctext = "<TEXTAREA NAME='DESC' ROWS=6 STYLE='width: 970px;'>$description</TEXTAREA>";

  # some buttons... #
  my $savebutton = "<INPUT TYPE=BUTTON VALUE='Save List' ID='Save' NAME='SAVE' ONCLICK='submitGS( \"SAVE\" );'>";
  my $showlistbutton = "<INPUT TYPE=BUTTON VALUE='Show List' ID='Showlist' NAME='SHOWLIST' ONCLICK='submitGS( \"SHOWLIST\" );'>";
  my $putinbutton = "<INPUT TYPE=BUTTON VALUE='->' ONCLICK='putGenomeIn();'>";
  my $takebackbutton = "<INPUT TYPE=BUTTON VALUE='<-' ONCLICK='takeGenomeBack();'>";

  # genomestable #
  my $genomestable = "<TABLE><TR><TD><B>List to choose from:</B></TD><TD></TD><TD><B>Created genome list</B></TD></TR><TR><TD>$glisttochoose</TD><TD><TABLE><TR><TD>$putinbutton</TD></TR><TR><TD>$takebackbutton</TD></TABLE></TD><TD>$glist</TD></TR></TABLE>\n";

  # right table #
  my $listinput = "<INPUT TYPE=TEXT ID='LISTINPUT' NAME='LISTINPUT' VALUE='$listname' STYLE='width: 350px;'>";
  my $listtable = "<DIV><TABLE><TR><TH>Name:</TD><TD>$seeduser".'_'."$listinput</TH></TR>\n";
  $listtable .= "<TR><TH>Genomes:</TH><TD>$genomestable</TD></TR>\n";
  $listtable .= "<TR><TH>Description:</TH><TD>$desctext</TD></TR>\n";
  $listtable .= "</TABLE>";
  $listtable .= "$savebutton</DIV>\n";

  my $lefttable = "<TABLE><TR><TD>$namelist</TD></TR><TR><TD>$showlistbutton</TD></TR></TABLE>\n";

  # CONTENT #
  my $content = "<H1>Genome Lists</H1>";
  $content .= "<P>Genome Lists are personal sets of genomes for a certain user. They can be used in different parts of the Subsystem Editor,<BR>e.g. to add sets of genomes to a subsystem, or highlight or color genomes belonging to a certain set.</P>";
  $content .= $self->start_form( 'form' );
  $content .= "<INPUT TYPE='HIDDEN' NAME='actionhidden' ID='actionhidden' VALUE=''>\n";

  $content .= "<TABLE><TR><TH>User</TH><TD>$seeduser</TD><TABLE>\n";

  $content .= "<H2>Lists</H2>";
  $content .= "<P>The following lists belong to the user $seeduser. Click on a list to edit it, or create a new genome list below.</P>\n";
#  $content .= "<TABLE><TR><TD>$lefttable</TD></TR><TR><TD>$listtable</TD></TR></TABLE>\n";
  $content .= "$lefttable\n";
  $content .= "<H2>Edit List</H2>\n";
  $content .= "<P>Edit the chosen list. A list should contain at least 2 genomes. A description is not mandatory but helps to determine the purpose of the list.</P>\n";
  $content .= $listtable."\n";

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

sub get_genome_lists {
  my ( $fig, $seeduser ) = @_;
  
  my @lists = GenomeLists::getListsForUser( $seeduser );

  return \@lists;
}

###################################################
# genome info comes from different scripts, parse #
# it out to get the raw genome ids as an array    #
###################################################
sub parse_genomes {
  my ( $gstring ) = @_;
  
  return [] if ( !defined( $gstring ) );

  my @genomes;
  my @gs = split( '~', $gstring );
  
  foreach my $g ( @gs ) {
    if ( $g =~ /genome\_checkbox\_(\d+\.\d+)/ ) {
      push @genomes, $1;
    }
    else {
      push @genomes, $g;
    }
  }

  # hash it now to make it unique
  my %gens = map { $_ => 1 } @genomes;
  @genomes = keys %gens;

  return \@genomes;
}

sub get_genome_genus_species {
  my ( $fig, $genomes ) = @_;
  
  my @gsgsp;
  foreach my $g ( sort @$genomes ) {
    my $genusspecies = $fig->genus_species( $g );
    $genusspecies .= " ( $g )";
    push @gsgsp, $genusspecies;
  }

  return \@gsgsp;
}
