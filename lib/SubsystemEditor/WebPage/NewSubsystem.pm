package SubsystemEditor::WebPage::NewSubsystem;

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
    else
    {
	$seeduser = $user->lastname . "_" . $user->firstname . "_user";
	$seeduser =~ s/\s+/_/g;
	my $pref = $dbmaster->Preferences->create({
	    user => $user,
	    name => 'SeedUser',
	    application => $ppoapplication,
	});
	$pref->value($seeduser);
    }
  }

  if ( $user ) {
    $can_alter = 1;
    $fig->set_user( $seeduser );
  }


  ##############################
  # Construct the page content #
  ##############################
 
  my $content = "<H2>Create New Subsystem</H2>";

  if ( $user && defined( $cgi->param( 'SUBMIT' ) ) ) {

    # set description and notes
    my $ssname = $cgi->param( 'SSNAME' );
    print STDERR $ssname." SSNAME\n";
    my $name = $ssname;
    $name =~ s/ /\_/g;

    my $subsystem = new Subsystem( $ssname, $fig, 0 );
    if ( defined( $subsystem ) ) {
      $self->application->add_message( 'warning', "There is already a subsystem named $ssname<BR>" );
    }
    else {
      $subsystem = new Subsystem( $name, $fig, 1 );
      
      my $descrp = $cgi->param( 'SSDESC' );
      chomp $descrp;
      $descrp .= "\n";
      $subsystem->set_description( $descrp );
      
      my $notes = $cgi->param( 'SSNOTES' );
      chomp $notes;
      $notes .= "\n";
      $subsystem->set_notes( $notes );
      
      my $curator = $seeduser;
      $subsystem->{curator} = $curator;
    
      my $right = $dbmaster->Rights->create( { name => 'edit',
					       scope => $user->get_user_scope,
					       data_type => 'subsystem',
					       data_id => $name,
					       granted => 1,
					       delegated => 0 } );
      
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
      
      # here we really edit the files in the subsystem directory #
      $subsystem->db_sync();
      $subsystem->write_subsystem();
      $self->make_exchangable( $name );

      undef $subsystem;
      $subsystem = new Subsystem( $ssname, $fig, 0 );
      $subsystem->db_sync();

      my $esc_name = uri_escape($name);
      $esc_name =~ s/'/&#39;/g;

      $self->application->add_message( 'info', "Your subsystem $ssname was created successfully.<BR>\nPlease click <A HREF='?page=ShowSubsystem&subsystem=$esc_name'>this link</A> to view you subsystem." );
    }
  }


  $content .= $self->start_form( 'form' );

  my $classification_stuff = get_classification_boxes( $fig, $cgi, );

  my $infotable = "<TABLE><TR><TH>Name:</TH><TD><INPUT TYPE=TEXT NAME='SSNAME' ID='SSNAME' STYLE='width: 772px;'></TD><TR>";
  if ( $user ) {
    $infotable .= "<TR><TH>Author:</TH><TD>".$seeduser."</TD></TR>";
  }
  else {
    $infotable .= "<TR><TH>Author:</TH><TD></TD></TR>";
  }
  $infotable .= "<TR><TH>Version:</TH><TD>1</TD></TR>";
  $infotable .= "<TR><TH>Description</TH><TD><TEXTAREA NAME='SSDESC' ROWS=6 STYLE='width: 772px;'></TEXTAREA></TD></TR>";
  $infotable .= "<TR><TH>Notes</TH><TD><TEXTAREA NAME='SSNOTES' ROWS=6 STYLE='width: 772px;'></TEXTAREA></TD></TR>";
  $infotable .= $classification_stuff;
  $infotable .= "</TABLE>";

  if ( $can_alter ) {
    $infotable .= "<INPUT TYPE=SUBMIT VALUE='Save Changes' ID='SUBMIT' NAME='SUBMIT'>";
  }

  $content .= $infotable;
  $content .= $self->end_form();

  return $content;
}



sub get_classification_boxes {
  my ( $fig, $cgi) = @_;
  my $classified = 1;

  my $sdContent = '';

  my @ssclassifications = $fig->all_subsystem_classifications();
  my $ssclass;
  foreach my $ssc ( @ssclassifications ) {
    next if ( ( !defined( $ssc->[0] ) ) || ( !defined( $ssc->[1] ) ) );
    next if ( ( $ssc->[0] eq '' ) || ( $ssc->[1] eq '' ) );
    next if ( ( $ssc->[0] =~ /^\s+$/ ) || ( $ssc->[1] =~ /^\s+$/ ) );
    push @{ $ssclass->{ $ssc->[0] } }, $ssc->[1];
  }


  my @options;
  foreach my $firstc ( keys %$ssclass ) {
    my $opt = "<SELECT SIZE=5 ID='$firstc' NAME='SUBSYSH2' STYLE='width: 386px;' class='hideme'>";
    my $optstring = '';
    foreach my $secc ( sort @{ $ssclass->{ $firstc } } ) {
      $optstring .= "<OPTION VALUE='$secc'>$secc</OPTION>";
    }
    $opt .= $optstring;
    $opt .= "</SELECT>";
    push @options, $opt;
  }
  
  $sdContent .= "<TR><TH><INPUT TYPE=\"RADIO\" NAME=\"Classification\" VALUE=\"Classified\" CHECKED onchange='radioclassification();'>Classification:</TH><TD><SELECT SIZE=5 ID='SUBSYSH1' NAME='SUBSYSH1' STYLE='width: 386px;' onclick='gethiddenoption();'>";

  foreach my $firstc ( sort keys %$ssclass ) {
    if ( $firstc eq 'Experimental Subsystems' ) {
      $sdContent .= "\n<OPTION SELECTED VALUE='$firstc'>$firstc</OPTION>\n";
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
  $sdContent .= "<TR><TH><INPUT TYPE=\"RADIO\" NAME=\"Classification\" VALUE=\"User-defined\" onchange='radioclassification();'>User-defined:</TH><TD><INPUT TYPE=TEXT  STYLE='width: 386px;' NAME='SUBSYSH1TF' ID='SUBSYSH1TF' VALUE='' DISABLED=\"DISABLED\"><INPUT TYPE=TEXT  STYLE='width: 386px;' NAME='SUBSYSH2TF' ID='SUBSYSH2TF' VALUE='' DISABLED=DISABLED></TD></TR>";

  return $sdContent;
}

sub supported_rights {
  
  return [ [ 'edit', 'subsystem', '*' ] ];

}

sub make_exchangable {
    my( $self, $ssa ) = @_;

    if (($ssa) &&
         (-s "$FIG_Config::data/Subsystems/$ssa/spreadsheet") &&
        open(TMP,">$FIG_Config::data/Subsystems/$ssa/EXCHANGABLE"))
    {
        print TMP "1\n";
        close(TMP);
        chmod(0777,"$FIG_Config::data/Subsystems/$ssa/EXCHANGABLE");
    }
}
