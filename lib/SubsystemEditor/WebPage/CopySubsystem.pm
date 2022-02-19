package SubsystemEditor::WebPage::CopySubsystem;

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
}

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
  my $application = $self->application();
  $self->application->show_login_user_info(1);

  # subsystem name and 'nice name' #
  my $name = $cgi->param( 'subsystem' );
  $name = uri_unescape( $name );
  $name =~ s/&#39/'/g;

  if ( $name =~ /subsystem\_checkbox\_(.*)/ ) {
    $name = $1;
  }

  my $ssname = $name;
  $ssname =~ s/\_/ /g;

  # look if someone is logged in and can write the subsystem #
  my $can_alter = 0;
  my $user = $self->application->session->user;
  if ( $user ) {
    if ( $user->has_right( $self->application, 'edit', 'subsystem', $name ) ) {
      $can_alter = 1;
    }
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
    $fig->set_user( $seeduser );
  }
  else {
    $self->application->add_message( 'warning', "No user defined, please log in first\n" );
    return "<H1>Copy subsystem $ssname</H1>";
  }

  my ( $comment, $error ) = ( "" );


  #########
  # TASKS #
  #########

  my $esc_name = uri_escape( $name );
  
   if ( $cgi->param( 'GOCOPY' ) && defined( $cgi->param( 'newssname' ) ) && $cgi->param( 'newssname' ) ne '' ) {
     my $newssname = $cgi->param( 'newssname' );
     
     my $subsystem = new Subsystem( $newssname, $fig, 0 );

     if ( defined( $subsystem ) ) {
       $self->application->add_message( 'warning', "There is already a subsystem named $newssname<BR>" );
     }
     else {
       my $usnewssname = $newssname;
       $newssname =~ s/ /\_/g;

       # get stuff from the old subsystem
       my $oldsubsystem = new Subsystem( $name, $fig, 0 );

       my $notes = $oldsubsystem->get_notes();
       my $description = $oldsubsystem->get_description();
       my $classification = $oldsubsystem->get_classification();
       my %hope_reactions = $oldsubsystem->get_hope_reactions();
       my %hope_reaction_notes = $oldsubsystem->get_hope_reaction_notes();
       my %hope_reaction_links = $oldsubsystem->get_hope_reaction_links();
       my $kegg_reactions = $oldsubsystem->get_reactions();
       my $emptycells = $oldsubsystem->get_emptycells();

       #
       # Scope newsubsystem to get cleanup right.
       #
       {
	   
	   my $newsubsystem = new Subsystem( $newssname, $fig, 1 );
	   
	   $newsubsystem->set_curator($seeduser);
	   $newsubsystem->add_to_subsystem( $name, [ 'all' ] );   
	   
	   if ( defined( $notes ) && $notes ne '' ) {
	       $newsubsystem->set_notes( $notes );
	   }
	   if ( defined( $description ) && $description ne '' ) {
	       $newsubsystem->set_description( $description );
	   }
	   $newsubsystem->set_classification( $classification );
	   
	   # hope reactions #
	   foreach my $r ( $oldsubsystem->get_roles() ) {
	       if ( defined( $hope_reactions{ $r } ) ) {
		   $newsubsystem->set_hope_reaction( $r, join( ',', @{ $hope_reactions{ $r } } ) );
	       }
	       if ( defined( $kegg_reactions->{ $r } ) ) {
		   $newsubsystem->set_reaction( $r, join( ',', @{ $kegg_reactions->{ $r } } ) );
	       }
	       if ( defined( $hope_reaction_notes{ $r } ) ) {
		   $newsubsystem->set_hope_reaction_note( $r, $hope_reaction_notes{ $r } );
	       }
	       if ( defined( $hope_reaction_links{ $r } ) ) {
		   $newsubsystem->set_hope_reaction_link( $r, $hope_reaction_links{ $r } );
	       }
	   }
	   
	   my $newemptycells;
	   foreach my $r ( $oldsubsystem->get_abbrs() ) {
	       foreach my $g ( keys %{ $emptycells->{ $r } } ) {
		   $newemptycells->{ $r }->{ $g } = $emptycells->{ $r }->{ $g };
	       }
	   }
	   $newsubsystem->set_emptycells( $newemptycells );
	   
	   # write spreadsheet #
	   $newsubsystem->write_subsystem();
       }

       #
       # And sync, loading the SS from scratch to ensure we get
       # all the data.
       #
       {
	   my $ss = Subsystem->new($newssname, $fig);
	   $ss->db_sync();
       }
       
       # give edit right
       my $newrights = $dbmaster->Rights->get_objects({ scope       => $user->get_user_scope,
							data_type   => 'subsystem',
							data_id     => $newssname,
							name        => 'edit'
						      });
       if ( scalar( @$newrights ) == 0 ) {
	 # now move edit rights, curator etc to the new name
	 my $right = $dbmaster->Rights->create( { name => 'edit',
						  scope => $user->get_user_scope,
						  data_type => 'subsystem',
						  data_id => $newssname,
						  granted => 1,
						  delegated => 0 } );
       }
       

       my @attrs = $fig->get_attributes( 'Subsystem:'.$esc_name );

       foreach my $att ( @attrs ) {
	 my ( $ss, $key, $value ) = @$att;
	 my $esc_newssname = uri_escape($newssname);
	 $fig->add_attribute( "Subsystem:$esc_newssname", "SUBSYSTEM_PUBMED_RELEVANT", $value );
       }
       
       my $newlink = "<A HREF='SubsysEditor.cgi?page=ShowSubsystem&subsystem=$newssname' target=_blank>$newssname<A>";
       $comment .= "Copied $ssname to $newlink!<BR>";
       $ssname = $usnewssname;
     }
   }

  my $content = "<H1>Copy subsystem $ssname</H1>";
  $content .= $self->start_form( 'manage' );

  $content .= "<TABLE><TR><TD>Copy To:</TD><TD><INPUT TYPE=TEXT NAME=\"newssname\" SIZE=70></TD></TR></TABLE>";
  $content .= "<INPUT TYPE=SUBMIT ID='GOCOPY' NAME='GOCOPY' VALUE='Copy Now !'>";
  
  $content .= "<INPUT TYPE=HIDDEN NAME='subsystem' ID='subsystem' VALUE='$esc_name'>";

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


sub supported_rights {
  
return [ [ 'login', '*', '*' ] ];

}
