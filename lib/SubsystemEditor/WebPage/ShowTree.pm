package SubsystemEditor::WebPage::ShowTree;

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
}

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
  my $application = $self->application;

  my $name = $cgi->param( 'subsystem' );
  my $ssname = $name;
  $ssname =~ s/\_/ /g;

  my $esc_name = uri_escape($name);

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
 
  ##############################
  # Construct the page content #
  ##############################

  my $content = "<H2>Subsystem Connections for Subsystem:  $ssname</H2>";
  $content .= "<P>The following table shows all connections of the current subsystem to other subsystems. Connections are Functional Roles, that are included in both subsystems.</P>";

  my @rows;
  my $sshash;
  my $ss = new Subsystem( $name, $fig, 0 );
  my @roles = $ss->get_roles();
  foreach my $role ( @roles ) {
    my @subsystems = $fig->function_to_subsystems( $role );
    foreach my $s ( @subsystems ) {
      next if ( $s eq $name );
      $sshash->{ $s } = 1;
      my $isauxrole = $fig->is_aux_role_in_subsystem( $s, $role );
      my $isauxroleword = 'no';
      if ( $isauxrole ) {
	$isauxroleword = 'yes';
      }
      
      my $slink = "<A HREF='SubsysEditor.cgi?page=ShowSubsystem&subsystem=$s' target=_blank>$s</A>";
      my $rolelink = "<A HREF='SubsysEditor.cgi?page=FunctionalRolePage&subsystem=$esc_name&fr=$role' target=_blank>$role</A>";

      push @rows, [ $rolelink, $slink, $isauxroleword ];
    }
  }

  # subsystems table
  my $sstable = $application->component( 'sstable' );
  my $sstable_columns = [ { name => 'Functional Role', sortable => 1, filter => 1 }, 
			  { name => 'Subsystem', sortable => 1, filter => 1 }, 
			  { name => 'Aux.', filter => 1 },
			];
  $sstable->columns( $sstable_columns );
  $sstable->data( \@rows );

  $content .= $sstable->output();

  return $content;
}


