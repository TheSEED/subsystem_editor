package SubsystemEditor::WebPage::ShowMissingWithMatches;

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
  $self->application->register_component( 'Hover', 'TableHoverComponent' );
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
  
  # subsystem name and 'nice name' #
  my $name = $cgi->param( 'subsystem' );
  my $ssname = $name;
  $ssname =~ s/\_/ /g;

  my @srs = $cgi->param( 'fr' );
  my %showroles = map { $_ => 1 } @srs;

  my @sg = $cgi->param( 'genome' );
  my @showgenomes = ();
  foreach my $sge ( @sg ) {
    if ( $sge =~ /genome\_checkbox\_(.*)/ ) {
      $sge = $1;
    }
    push @showgenomes, $sge;
  }

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
  }

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
$content .= "<STYLE>td {border: 1px solid black; padding: 3px; font-size: 10pt} table {border-spacing: 0px; } body {font-family: Helvetica; font-size: 10pt;} th {border: 1px solid black; padding: 3px; font-size: 10pt}</STYLE><BR>";
  $content .= "<H1>Show missing with matches for subsystem $ssname</H2>";
  my $subsystem = new Subsystem( $name, $fig, 0 );

#  $content .= $self->start_form( 'form', { subsystem => $name } );
  my @html;
  my @tabs;
  &format_missing_including_matches( $fig, $cgi, \@html, \%showroles, \@showgenomes, $subsystem, $seeduser, $can_alter );

  foreach my $h ( @html ) {
    $content .= $h;
  }

#  $content .= $self->end_form();

  return $content;
}

sub supported_rights {
  
  return [ [ 'edit', 'subsystem', '*' ] ];

}


sub format_missing_including_matches {
  my($fig,$cgi,$html, $showroles, $showgenomes, $subsystem, $seeduser, $can_alter) = @_;
  my($org,$abr,$role,$missing);
  
  my $datahash = {};
  
  my @subsetC = $subsystem->get_roles();

  my %activeC;
  if ( defined( $showroles ) && scalar( keys %$showroles ) > 0 ) {
    foreach my $abk ( keys %$showroles ) {
      my $r = $subsystem->get_role_from_abbr( $abk );
      $activeC{ $r } = 1;
    }
  }
  else {
    %activeC = map { $_ => 1 } @subsetC;
  }
  @subsetC = keys %activeC;

  my @subsetR = $subsystem->get_genomes();

   if ( defined( $showgenomes ) && scalar( @$showgenomes ) > 0) {
     @subsetR = @$showgenomes;
   }
  
  my @alt_sets = grep { ($_ =~ /^\*/) } sort $subsystem->get_subset_namesC;
  my($set,$col,%in);
  foreach $set (@alt_sets) {
    my @mem = grep { $activeC{$_} } $subsystem->get_subsetC_roles($set);
    foreach $col (@mem) {
      $in{$col} = $set;
    }
  }
 
  if ( $can_alter ) {
    push(@$html, $cgi->start_form(-action=> "fid_checked.cgi"));
  }

  push(@$html,
       $cgi->hidden(-name => 'user', -value => $seeduser, -override => 1),
       $cgi->hidden(-name => 'can_alter', -value => $can_alter, -override => 1));
  
  my $just_role = &which_role($subsystem,$cgi->param('just_role'));

  foreach $org (@subsetR) {

    my $loc;
    my $raworg = $org;
    if ( $org =~ /(\d+\.\d+)\:(.*)/ ) {
      $raworg = $1;
      $loc = $2;
    }

    my @missing = &columns_missing_entries($cgi,$subsystem,$org,\@subsetC,\%in);
    $missing = [];
    foreach $role (@missing) {

      next if ($just_role && ($just_role ne $role));
      
      my @hits = $fig->find_role_in_org($role, $raworg, $seeduser, $cgi->param("sims_cutoff"));
      push(@$missing,@hits);
    }
    if (@$missing > 0) {
      my $genus_species = &ext_genus_species($fig,$raworg);
      push(@$html,$cgi->h2("$org: $genus_species"));
      
      my $colhdr;
      if ( $can_alter ) {
	$colhdr = ["Assign", "P-Sc", "PEG", "Len", "Current fn", "Matched peg", "Len", "Function"];
      }
      else {
	$colhdr = ["P-Sc", "PEG", "Len", "Current fn", "Matched peg", "Len", "Function"];
      }
      my $tbl = [];
      
      for my $hit (@$missing) {
	my($psc, $my_peg, $my_len, $my_fn, $match_peg, $match_len, $match_fn) = @$hit;

	if ( defined( $loc ) ) {
	  my ( $contig_reg, $beg_reg, $end_reg ) = $fig->boundaries_of( $loc );

	  my $loc_hit = $fig->feature_location( $my_peg );
	  my ( $contig_hit, $beg_hit, $end_hit ) = $fig->boundaries_of( $loc_hit );

	  next if ( $contig_reg ne $contig_hit );
	  next if ( $beg_reg > $beg_hit );
	  next if ( $end_reg < $end_hit );
	}

	$my_peg =~ /fig\|\d+\.\d+\.peg\.(\d+)/;
	my $n = $1;
	my $my_peg_link = fid_link( $my_peg, $seeduser );
	$my_peg_link = "<A HREF='$my_peg_link' target=_blank>$n</A>";

	$match_peg =~ /fig\|\d+\.\d+\.peg\.(\d+)/;
	$n = $1;
	my $match_peg_link = fid_link( $match_peg, $seeduser );
	$match_peg_link = "<A HREF='$match_peg_link' target=_blank>$match_peg</A>";
	
	my $checkbox = $cgi->checkbox(-name => "checked",
				      -value => "to=$my_peg,from=$match_peg",
				      -label => "");
	
	if ( $can_alter ) {
	  push(@$tbl, [$checkbox,
		       $psc,
		       $my_peg_link, $my_len, $my_fn,
		       $match_peg_link, $match_len, $match_fn]);
	}
	else {
	  push(@$tbl, [$psc,
		       $my_peg_link, $my_len, $my_fn,
		       $match_peg_link, $match_len, $match_fn]);
	}
      }
      
      push(@$html, &HTML::make_table($colhdr, $tbl, ""));
    }
  }
  if ( $can_alter ) {
    push(@$html,
	 $cgi->submit(-value => "Process assignments",
		      -name => "batch_assign"),
	 $cgi->end_form);
  }
  
}

sub which_role {
    my($subsystem,$role_indicator) = @_;
    my($n,$role,$abbr);

    if (($role_indicator =~ /^\s*(\d+)\s*$/) && ($n = $1) && ($role = $subsystem->get_role($n-1)))
    {
        return $role;
    }
    elsif (($role_indicator =~ /^\s*(\S+)\s*$/) && ($abbr = $1) && ($role = $subsystem->get_role_from_abbr($abbr)))
    {
        return $role;
    }
    return "";
}

sub columns_missing_entries {
    my($cgi,$subsystem,$org,$roles,$in) = @_;

    my $just_genome = $cgi->param('just_genome');
    if ($just_genome && ($just_genome =~ /(\d+\.\d+)/) && ($org != $1)) { return () }

    my $just_col = $cgi->param('just_col');
    my(@really_missing) = ();

    my($role,%missing_cols);
    foreach $role (@$roles) {
        next if ($just_col && ($role ne $just_col));
        if ($subsystem->get_pegs_from_cell($org,$role) == 0)
        {
            $missing_cols{$role} = 1;
        }
    }

    foreach $role (@$roles)
    {
        if ($missing_cols{$role})
        {
            my($set);
            if (($set = $in->{$role}) && (! $cgi->param('ignore_alt')))
            {
                my @set = $subsystem->get_subsetC_roles($set);

                my($k);
                for ($k=0; ($k < @set) && $missing_cols{$set[$k]}; $k++) {}
                if ($k == @set)
                {
                    push(@really_missing,$role);
                }
            }
            else
            {
                push(@really_missing,$role);
            }
        }
    }
    return @really_missing;
}

sub ext_genus_species {
    my( $fig, $genome ) = @_;

    my ( $gs, $c ) = $fig->genus_species_domain( $genome );
    $c = ( $c =~ m/^Environ/i ) ? 'M' : substr($c, 0, 1);  # M for metagenomic
    return "$gs [$c]";
}

sub fid_link {
    my ( $fid, $seeduser ) = @_;
    my $n;

    if ($fid =~ /^fig\|\d+\.\d+\.([a-zA-Z]+)\.(\d+)/) {
      if ( $1 eq "peg" ) {
	  $n = $2;
	}
      else {
	  $n = "$1.$2";
	}
    }

#    return "./protein.cgi?prot=$fid&user=$seeduser\&new_framework=0";
    return qq~./seedviewer.cgi?page=Annotation&feature=$fid&user=$seeduser~;
}
