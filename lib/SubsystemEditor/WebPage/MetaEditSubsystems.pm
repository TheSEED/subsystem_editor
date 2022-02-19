package SubsystemEditor::WebPage::MetaEditSubsystems;

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
  $self->{ 'cgi' } = $application->cgi;
  
  # subsystem name and 'nice name' #
  my $name = $self->{ 'cgi' }->param( 'metasubsystem' );
  my $ssname = $name;

  my $esc_name = uri_escape( $name );

  $ssname =~ s/\_/ /g;

  # look if someone is logged in and can write the subsystem #
  $self->{ 'can_alter' } = 0;
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

  $self->{ 'metasubsystem' } = new MetaSubsystem( $name, $self->{ 'fig' }, 0 );
  if ( !defined( $self->{ 'metasubsystem' } ) ) {
    my $content = '<H1>Add / Remove Subsystems</H1>';
    $content .= "Subsystem $ssname does not exist!";
    return $content;
  }

  if ( $user ) {
    if ( $user->has_right( $self->application, 'edit', 'metasubsystem', $name ) ) {
      $self->{ 'can_alter' } = 1;
      $self->{ 'fig' }->set_user( $seeduser );
    }
    else {
      # we might have the problem that the user has not yet got the right for editing the
      # subsystem due to that it was created in the old seed or what do I know where.
      my $curatorOfSS = $self->{ 'metasubsystem' }->get_curator();

      my $su = lc( $seeduser );
      my $cu = lc( $curatorOfSS );
      if ( $su eq $cu ) {
	# now set the rights... 
	my $right = $dbmaster->Rights->create( { name => 'edit',
						 scope => $user->get_user_scope,
						 data_type => 'metasubsystem',
						 data_id => $name,
						 granted => 1,
						 delegated => 0 } );
	if ( $right ) {
	  $self->{ 'can_alter' } = 1;
	  $self->{ 'fig' }->set_user( $seeduser );
	}
      }
    }
  }

  my $hiddenvalues = {};
  my $build_subsets_string = '';

  my ( $error, $comment ) = ( "", "" );

  #########
  # TASKS #
  #########

  if ( defined( $self->{ 'cgi' }->param( 'ADDSUBMIT' ) ) ) {

    my @chosen_subsystems = $self->{ 'cgi' }->param( 'the_subsystems' );
    my $subsystems = $self->{ 'metasubsystem' }->{ 'subsystems' };
    foreach my $ssname ( keys %$subsystems ) {
      push @chosen_subsystems, $ssname;
    }

    my %newsubsystems = map { $_ => 1 } @chosen_subsystems;

    $self->{ 'metasubsystem' }->{ 'subsystems' } = \%newsubsystems;
    $self->{ 'metasubsystem' }->incr_version();
    $self->{ 'metasubsystem' }->write_metasubsystem();

    $self->{ 'metasubsystem' } = new MetaSubsystem( $name, $self->{ 'fig' }, 0 );
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'REMOVESUBMIT' ) ) ) {

    my @chosen_subsystems = $self->{ 'cgi' }->param( 'del_subsystems' );
    my $subsystems = $self->{ 'metasubsystem' }->{ 'subsystems' };
    foreach my $ssname ( @chosen_subsystems ) {
      delete $self->{ 'metasubsystem' }->{ 'subsystems' }->{ $ssname };

      # care about subsets...
      foreach my $subs ( keys %{ $self->{ 'metasubsystem' }->{ 'subsets' } } ) {
	foreach my $sub ( keys %{ $self->{ 'metasubsystem' }->{ 'subsets' }->{ $subs } } ) {
	  chomp $sub;
	  if ( $sub =~ /(.*)##-##(.*)/ ) {
	    if ( $2 eq $ssname ) {
	      delete $self->{ 'metasubsystem' }->{ 'subsets' }->{ $subs }->{ $sub };
	    }
	  }
	}
      }
    }

    $self->{ 'metasubsystem' }->incr_version();
    $self->{ 'metasubsystem' }->write_metasubsystem();

    $self->{ 'metasubsystem' } = new MetaSubsystem( $name, $self->{ 'fig' }, 0 );
  }

  ######################
  # Construct the menu #
  ######################

  my $menu = $self->application->menu();

  # Build nice tab menu here
  $menu->add_category( 'Meta Overview', "SubsysEditor.cgi?page=MetaOverview" );
  $menu->add_category( 'Info', "SubsysEditor.cgi?page=MetaInfo&metasubsystem=$esc_name" );
  $menu->add_category( 'Edit Subsets', "SubsysEditor.cgi?page=MetaSubsets&metasubsystem=$esc_name" );
  $menu->add_category( 'Add/Remove Subsystems', "SubsysEditor.cgi?page=MetaEditSubsystems&metasubsystem=$esc_name" );
  $menu->add_category( 'Spreadsheet', "SubsysEditor.cgi?page=MetaSpreadsheet&metasubsystem=$esc_name" );

  ##############################
  # Construct the page content #
  ##############################

  my $choose = $self->choose_subsystems();
  my $remove = $self->remove_subsystems();

  my $content = "<H1>Add / Remove Subsystems $ssname</H1>";
  $content .= '<H2>Choose Subsystems to Add to the MetaSubsystem</H2>';
  $content .= $self->start_form( 'form', { metasubsystem => $name } );
  $content .= $choose;
  $content .= '<BR>';
  $content .= '<H2>Choose Subsystems to Remove from the MetaSubsystem</H2>';
  $content .= $remove;
  $content .= $self->end_form();

  return $content;
}


sub choose_subsystems {
  
  my ( $self ) = @_;

  my $panel = '';
  my $subsystems = $self->{ 'metasubsystem' }->{ 'subsystems' };
  my @subsystems = sort $self->{ 'fig' }->all_subsystems();
  my %subsystemse = map { $_ => 1 } @subsystems;

  foreach my $ssname ( keys %$subsystems ) {
    my $subsystem = $subsystems->{ $ssname };
    delete $subsystemse{ $subsystem };
  }
  my @sss = sort keys %subsystemse;

  # now special sets #
  $panel .= $self->{ 'cgi' }->scrolling_list( -id       => 'the_subsystems', 
					      -name     => 'the_subsystems',
					      -values   => \@sss,
					      -default  => 'None',
					      -size     => 10,
					      -multiple => 1
					    );
  
  $panel .= "<BR><INPUT TYPE=SUBMIT VALUE='ADD' NAME='ADDSUBMIT'>";

  return $panel;
}

sub remove_subsystems {
  
  my ( $self ) = @_;

  my $panel = '';
  my $subsystems = $self->{ 'metasubsystem' }->{ 'subsystems' };

  my @sss = keys %$subsystems;

  # now special sets #
  $panel .= $self->{ 'cgi' }->scrolling_list( -id       => 'del_subsystems', 
					      -name     => 'del_subsystems',
					      -values   => \@sss,
					      -default  => 'None',
					      -size     => 5,
					      -multiple => 1
					    );
  
  $panel .= "<BR><INPUT TYPE=SUBMIT VALUE='REMOVE' NAME='REMOVESUBMIT'>";

  return $panel;
}
