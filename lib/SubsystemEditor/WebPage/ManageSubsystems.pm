package SubsystemEditor::WebPage::ManageSubsystems;

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

  $self->application->register_component( 'Table', 'retttable' );
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
  
  $self->{ 'fig' } = $self->application->data_handle( 'FIG' );
  $self->{ 'cgi' } = $self->application->cgi;
  my $application = $self->application();
  $self->application->show_login_user_info(1);
  $self->{ 'alleditable' } = $self->{ 'cgi' }->param( 'alleditable' );

  # look if someone is logged in and can write the subsystem #
  $self->{ 'can_alter' } = 0;
  my $user = $self->application->session->user;
  if ( $user ) {
    $self->{ 'can_alter' } = 1;
  }

  my $dbmaster = $self->application->dbmaster;
  my $ppoapplication = $self->application->backend;

  my $content = "<H1>Manage my subsystems</H1>";

  # get a seeduser #
  my $seeduser = '';
  if ( defined( $user ) && ref( $user ) ) {
    my $preferences = $dbmaster->Preferences->get_objects( { user => $user,
							     name => 'SeedUser',
							     application => $ppoapplication } );
    if ( defined( $preferences->[0] ) ) {
      $seeduser = $preferences->[0]->value();
    }
    $self->{ 'fig' }->set_user( $seeduser );
  }
  else {
    $self->application->add_message( 'warning', "No user defined, please log in first\n" );
    return "<H1>Manage my subsystems</H1>";
  }

  my ( $comment, $error ) = ( "" );

  my $ss_rights = $user->has_right_to($self->application, 'edit', 'subsystem');
  $self->{ss_rights} = { map { $_ => 1 } @$ss_rights };

  #########
  # TASKS #
  #########

  
  if ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'DeleteSubsystems' ) {
    my @sstodelete = $self->{ 'cgi' }->param( 'subsystem_checkbox' );
    foreach my $sstd ( @sstodelete ) {
      if ( $sstd =~ /subsystem\_checkbox\_(.*)/ ) {
	my $ss = $1;
	$ss = uri_unescape( $ss );
	$ss =~ s/&#39/'/g;
	$comment = $self->remove_subsystem( $ss );
      }
    }
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'buttonpressed' ) ) && $self->{ 'cgi' }->param( 'buttonpressed' ) eq 'RenameSubsystem' ) {
    my @sstorename = $self->{ 'cgi' }->param( 'subsystem_checkbox' );
    if ( scalar( @sstorename ) < 1 ) {
      $error = "No subsystem selected for renaming<BR>";
    }
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'MakePrivate' ) ) ) {
    my @sstorename = $self->{ 'cgi' }->param( 'subsystem_checkbox' );
    foreach my $sstd ( @sstorename ) {
      if ( $sstd =~ /subsystem\_checkbox\_(.*)/ ) {
	my $ss = $1;
	$ss = uri_unescape( $ss );
	$ss =~ s/&#39/'/g;
	$self->make_unexchangable( $ss );
	$comment .= "$ss is now a private subsystem<BR>\n";
      }
    }
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'MakeNotPrivate' ) ) ) {
    my @sstorename = $self->{ 'cgi' }->param( 'subsystem_checkbox' );
    foreach my $sstd ( @sstorename ) {
      if ( $sstd =~ /subsystem\_checkbox\_(.*)/ ) {
	my $ss = $1;
	$ss = uri_unescape( $ss );
	$ss =~ s/&#39/'/g;
	$self->make_exchangable( $ss );
	$comment .= "$ss is no more a private subsystem<BR>\n";
      }
    }
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'ReindexSS' ) ) ) {
    my @sstorename = $self->{ 'cgi' }->param( 'subsystem_checkbox' );
    my @ss;

    foreach my $sstd ( @sstorename ) {
      if ( $sstd =~ /subsystem\_checkbox\_(.*)/ ) {
	my $s = $1;
	$s = uri_unescape( $s );
	$s =~ s/&#39/'/g;
	push @ss, $s;
      }
    }

    my $job = $self->{ 'fig' }->index_subsystems( @ss );
    $comment .= "<H2>ReIndexing these subsystems...</H2>\n<ul>";
    foreach my $s ( @ss ) {
      $s = uri_unescape( $s );
      $s =~ s/&#39/'/g;
      $comment .= "<li>". $s ."</li>" ;
    }
    
    $comment .= "</ul>\n<p>... is running in the background with job id $job. You may check it in the ";
    $comment .= "<a href=\"seed_ctl.cgi?user=$seeduser\">SEED Control Panel</a></p>\n";
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'PublishSS' ) ) ) {
    my @sstorename = $self->{ 'cgi' }->param( 'subsystem_checkbox' );
    my @ss;

    foreach my $sstd ( @sstorename ) {
      if ( $sstd =~ /subsystem\_checkbox\_(.*)/ ) {
	my $s = $1;
	$s = uri_unescape( $s );
	$s =~ s/&#39/'/g;
	push @ss, $s;
      }
    }
    
    my ( $ch ) = $self->{ 'fig' }->get_clearinghouse();
    if ( !defined( $ch ) ) {
      $error .= "cannot publish: clearinghouse not available\n";
    }
    else {
      
	# print $self->{ 'cgi' }->header();
	# print $self->{ 'cgi' }->start_html();
	foreach my $ssa ( @ss ) {
	    $content .= "<B>Publishing $ssa to clearinghouse...</B><BR>\n";
	    $| = 1;
	    my $res = $self->{ 'fig' }->publish_subsystem_to_clearinghouse( $ssa, undef, 1);
	    if ($res) {
		$res =~ s/\n/<br>\n/;
		$content .= "Published <i>$ssa </i> to clearinghouse<br>$res\n";
	    }
	    else {
		$content .= "<b>Failed</b> to publish <i>$ssa</i> to clearinghouse<br>\n";
	    }
	}
    }
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'ExtendableSS' ) ) ) {
    my @sstorename = $self->{ 'cgi' }->param( 'subsystem_checkbox' );
    foreach my $sstd ( @sstorename ) {
      if ( $sstd =~ /subsystem\_checkbox\_(.*)/ ) {
	my $ss = $1;
	$ss = uri_unescape( $ss );
	$ss =~ s/&#39/'/g;
	$self->{ 'fig' }->ok_to_auto_update_subsys( $ss, 1 );
	$comment .= "$ss is now an automatically extendable<BR>\n";
      }
    }
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'NOTExtendableSS' ) ) ) {
    my @sstorename = $self->{ 'cgi' }->param( 'subsystem_checkbox' );
    foreach my $sstd ( @sstorename ) {
      if ( $sstd =~ /subsystem\_checkbox\_(.*)/ ) {
	my $ss = $1;
	$ss = uri_unescape( $ss );
	$ss =~ s/&#39/'/g;
	$self->{ 'fig' }->ok_to_auto_update_subsys( $ss, -1 );
	$comment .= "$ss is now an automatically extendable<BR>\n";
      }
    }
  }



  # spreadsheetbuttons #
  my $actionbuttons = $self->get_spreadsheet_buttons( $application );
  
  my $hiddenvalues;
  $hiddenvalues->{ 'buttonpressed' } = 'none';
  $hiddenvalues->{ 'alleditable' } = $self->{ 'alleditable' };


  if ( defined( $comment ) && $comment ne '' ) {
    my $info_component = $application->component( 'CommentInfo' );

    $info_component->content( $comment );
    $info_component->default( 0 );
    $content .= $info_component->output();
  }    

  $content .= $self->start_form( 'manage', $hiddenvalues );

  my ( $sstable, $putcomment ) = $self->getSubsystemTable( $user, $seeduser );
  $comment .= $putcomment;

  $content .= $actionbuttons;
  $content .= $sstable;
  $content .= $actionbuttons;

  $content .= $self->end_form();

  ###############################
  # Display errors and comments #
  ###############################
 
  if ( defined( $error ) && $error ne '' ) {
    $self->application->add_message( 'warning', $error );
  }

  return $content;
}


####################################
# get the subsystem overview table #
####################################
sub getSubsystemTable {
  
  my ( $self, $user, $seeduser ) = @_;
  
  my $comment = '';

  my $showright = defined( $self->{ 'cgi' }->param( 'SHOWRIGHT' ) );
  my $showmine = defined( $self->{ 'cgi' }->param( 'SHOWMINE' ) );

  my $rettable;
  
  my @sss = $self->{fig}->all_subsystems_detailed();
  
  my $retcolumns = [ '',
  		     { 'name' => 'Subsystem Name',
		       'width' => 300,
		       'sortable' => 1,
		       'filter'   => 1 },
		     { 'name' => 'Version',
		       'sortable' => 1 },
		     { 'name' => 'Subsystem Curator' },
		     { 'name' => 'Private<BR>Subsystem' },
		     { 'name' => 'Automatically<BR>Extendable' },
		     { 'name' => 'Split<BR>Subsystem' },
		     { 'name' => 'Change<BR>Curator' },
  		   ];
  
  my $retdata = [];

  foreach my $ss ( @sss ) {
    my $name = $ss->{subsystem};
warn Dumper($ss);
    my $esc_name = uri_escape( $name );
    
#    my ( $ssversion, $sscurator, $pedigree, $ssroles ) = $self->{ 'fig' }->subsystem_info( $name );

    my $ssversion = $ss->{version};
    my $sscurator = $ss->{curator};
    
    
    my $private_ss = ( $self->{ 'fig' }->is_private_subsystem( $name ) ? 'yes' : 'no' );
    my $ext_ss = ( $self->{ 'fig' }->ok_to_auto_update_subsys( $name ) ? 'yes' : 'no' );

    my $can_edit_this = $self->{ss_rights}->{'*'} || $self->{ss_rights}->{$name};
    if ( $self->{ 'alleditable' } && $can_edit_this || $sscurator eq $seeduser ) {
      $self->{ 'can_alter' } = 1;
      $self->{ 'fig' }->set_user( $seeduser );
    }
    else {
      next;
    }


    if ( $self->{ 'can_alter' } ) {
     $ssversion .= " -- <A HREF='".$self->application->url()."?page=ResetSubsystem&subsystem=$esc_name' target='_blank'>Reset</A>";
    }

    if ( defined( $name ) && $name ne '' && $name ne ' ' ) {  

      my $ssname = $name;
      $ssname =~ s/\_/ /g;

      if ( $name =~ /'/ ) {
	$name =~ s/'/&#39/;
      }

      my $esc_name = uri_escape($name);

      my $subsysurl = "SubsysEditor.cgi?page=ShowSubsystem&subsystem=$esc_name";
      my $split_link = "SubsysEditor.cgi?page=SplitSubsystem&subsystem=$esc_name";
      my $chown_link = "SubsysEditor.cgi?page=ChangeCuratorSubsystem&subsystem=$esc_name";
      
      my $subsystem_checkbox = $self->{ 'cgi' }->checkbox( -name     => 'subsystem_checkbox',
					       -id       => "subsystem_checkbox_$esc_name",
					       -value    => "subsystem_checkbox_$esc_name",
					       -label    => '',
					       -checked  => 0,
					       -override => 1 );
      
      my $retrow = [ #$class->[0], 
		    #		     $class->[1], 
		    $subsystem_checkbox,
		    "<A HREF='$subsysurl'>$ssname</A>",
		    $ssversion, 
		    $sscurator, 
		    $private_ss, 
		    $ext_ss,
		    "<A HREF='$split_link'>split</A>",
		    "<A HREF='$chown_link'>change curator</A>" ];
      push @$retdata, $retrow;
    }
  }
  
  my $rettableobject = $self->application->component( 'retttable' );
  $rettableobject->width( 900 );
  $rettableobject->data( $retdata );
  $rettableobject->columns( $retcolumns );
  $rettable = $rettableobject->output();
  
  return ( $rettable, $comment );
}

sub supported_rights {
  
return [ [ 'login', '*', '*' ] ];

}

#################################
# Buttons under the spreadsheet #
#################################
sub get_spreadsheet_buttons {

  my ( $self, $application ) = @_;
  
  my $delete_button = "<INPUT TYPE=HIDDEN VALUE=0 NAME='DeleteSS' ID='DeleteSS'>";
  $delete_button .= "<INPUT TYPE=BUTTON VALUE='Delete selected subsystems' NAME='DeleteSubsystems' ID='DeleteSubsystems' ONCLICK='if ( confirm( \"Do you really want to delete the selected subsystems?\" ) ) { 
 document.getElementById( \"DeleteSS\" ).value = 1;
SubmitManage( \"DeleteSubsystems\", 0 ); }'>";

  my $rename_ss_button = "<INPUT TYPE=HIDDEN VALUE=0 NAME='RenameSS' ID='RenameSS'>";
  $rename_ss_button .= "<INPUT TYPE=BUTTON VALUE='Rename selected subsystem' NAME='RenameSubsystem' ID='RenameSubsystem' ONCLICK='OpenRenameSubsystem( \"".$application->url()."\" );'>";

  my $make_private_button .= "<INPUT TYPE=SUBMIT VALUE='Make subsystems Private' NAME='MakePrivate' ID='MakePrivate'>";
  my $make_not_private_button .= "<INPUT TYPE=SUBMIT VALUE='Make subsystems NOT Private' NAME='MakeNotPrivate' ID='MakeNotPrivate'>";
  my $extendable_button .= "<INPUT TYPE=SUBMIT VALUE='Make Autom. Extendable' NAME='ExtendableSS' ID='ExtendableSS'>"; 
  my $not_extendable_button .= "<INPUT TYPE=SUBMIT VALUE='Make NOT Autom. Extendable' NAME='NOTExtendableSS' ID='NOTExtendableSS'>";
  my $publish_button .= "<INPUT TYPE=SUBMIT VALUE='Publish Subsystems to Clearinghouse' NAME='PublishSS' ID='PublishSS'>";
  my $reindex_button .= "<INPUT TYPE=SUBMIT VALUE='Reindex Subsystems' NAME='ReindexSS' ID='ReindexSS'>";
  
  my $spreadsheetbuttons = "<DIV id='controlpanel'><H2>Actions</H2>\n";
  if ( $self->{ 'can_alter' } ) {
    $spreadsheetbuttons .= "<TABLE><TR><TD$delete_button</TD><TD>$rename_ss_button</TD><TD>$make_private_button</TD><TD>$make_not_private_button</TD></TR></TABLE><BR>";
#    $spreadsheetbuttons .= "<TABLE><TR><TD>$extendable_button</TD><TD>$not_extendable_button</TD><TD>$publish_button</TD><TD$reindex_button</TD></TR></TABLE><BR>";
    $spreadsheetbuttons .= "<TABLE><TR><TD>$extendable_button</TD><TD>$not_extendable_button</TD><TD>$publish_button</TD></TR></TABLE><BR>";
  }
  $spreadsheetbuttons .= "</DIV>";
  return $spreadsheetbuttons;
}

#######################################
# Remove genomes from the spreadsheet #
#######################################
sub remove_subsystem {
  my( $self, $subsystem ) = @_;

  my $sub = $self->{ 'fig' }->get_subsystem( $subsystem );
  $sub->delete_indices();

#  $subsystem =~ s/'/\\'/g;
  my $name = $subsystem;
  $name =~ s/\_/ /g;
  
#  my $cmd = "rm -rf '$FIG_Config::data/Subsystems/$subsystem'";
  $self->{ 'fig' }->verify_dir( "$FIG_Config::data/SubsystemsBACKUP" );
  my $cmd = "mv $FIG_Config::data/Subsystems/$subsystem $FIG_Config::data/SubsystemsBACKUP/$subsystem"."_".time;
  $cmd =~ s/'/\\'/g;
  $cmd =~ s/\(/\\\(/g;
  $cmd =~ s/\)/\\\)/g;

  my $rc = system $cmd;
  
  my $comment = "Deleted subsystem $name<BR>\n";

  $self->{fig}->flush_subsystem_cache();
  return $comment;
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
    $self->{fig}->subsystem_metadata_update($ssa, exchangable => 1);
}

#sub make_unexchangable {
#    my( $self, $ssa ) = @_;
#
#    if (($ssa) &&
#         (-s "$FIG_Config::data/Subsystems/$ssa/EXCHANGABLE"))
#    {
#        unlink("$FIG_Config::data/Subsystems/$ssa/EXCHANGABLE");
#    }
#}

sub make_unexchangable {
    my( $self, $ssa ) = @_;

    if (($ssa) &&
         (-s "$FIG_Config::data/Subsystems/$ssa/spreadsheet") &&
        open(TMP,">$FIG_Config::data/Subsystems/$ssa/EXCHANGABLE"))
    {
        print TMP "0\n";
        close(TMP);
        chmod(0777,"$FIG_Config::data/Subsystems/$ssa/EXCHANGABLE");
    }
    $self->{fig}->subsystem_metadata_update($ssa, exchangable => 0);
}
