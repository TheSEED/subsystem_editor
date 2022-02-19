package SubsystemEditor::WebPage::ProposeNewPeg;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;

use FIGjs          qw( toolTipScript );
use GenoGraphics   qw( render );

use FIG;

use FIG_CGI;
use strict;
use gjoseqlib     qw( %genetic_code );
use gjoparseblast qw( blast_hsp_list next_blast_hsp );

use URI::Escape;  # uri_escape
use POSIX;
use HTML;

use base qw( WebPage );

1;

##############################################################
# Method for registering components etc. for the application #
##############################################################
sub init {
  my ( $self ) = @_;
  $self->application->register_component( 'TabView', 'functionTabView' );
  $self->application->register_component( 'Table', 'SimsTable' );
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

  $self->{ 'fig' } = $self->application->data_handle( 'FIG' );
  $self->{ 'cgi' } = $self->application->cgi;
  $self->{ 'genome' } = $self->{ 'cgi' }->param( 'genome' );
  $self->{ 'organism' } = $self->{ 'fig' }->genus_species( $self->{ 'genome' } );
  $self->{ 'location' } = $self->{ 'cgi' }->param( 'location' );
  $self->{ 'covering' } = $self->{ 'cgi' }->param( 'covering' );
  $self->{ 'old_peg' } = $self->{ 'cgi' }->param( 'fid' );

  if ( defined( $self->{ 'old_peg' } ) ) {
    $self->{ 'location' } = $self->{ 'fig' }->feature_location( $self->{ 'old_peg' } );
    $self->{ 'genome' } = $self->{ 'fig' }->genome_of( $self->{ 'old_peg' } );
    $self->{ 'organism' } = $self->{ 'fig' }->genus_species( $self->{ 'genome' } );
    $self->{ 'function' } = $self->{ 'fig' }->function_of( $self->{ 'old_peg' } );
  }
  
  #  Extra triplets around selected orf in a BLASTP search
  $self->{ 'blast_pad' } = $self->{ 'cgi' }->param(' blast_pad' );
  defined( $self->{ 'blast_pad' } ) or $self->{ 'blast_pad' } = 20;

#  Is BLASTP being requested?
  $self->{ 'blastp' } = $self->{ 'cgi' }->param( 'blastp' ) || undef;


  my $error = '';

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
  $self->{ 'seeduser' } = '';

  $self->{ 'can_alter' } = 0;
  if ( defined( $preferences->{ 'SeedUser' } ) ) {
    $self->{ 'seeduser' } = $preferences->{ 'SeedUser' }->value;
  }
  if ( $user ) {
    $self->{ 'can_alter' } = 1;
    if (!$self->{seeduser})
    {
	$self->{seeduser} = $user->login;
    }

    $self->{ 'seeduser' } = $user;
    $self->{ 'fig' }->set_user( $self->{ 'seeduser' } );
  }

  my $extra = 270;
  
  #---------------------------------------------------------------------------
  #  What is the current set of allowed start codons?
  #---------------------------------------------------------------------------
  
  my @is_start = $self->{ 'cgi' }->param('is_start');
  ( @is_start > 0 ) or ( @is_start = qw( ATG GTG TTG ) );
  my %is_start = map { $_ => 1 } @is_start;
  
  #---------------------------------------------------------------------------
  #  What genetic code do we use?
  #---------------------------------------------------------------------------
  
  my %gencode = map { $_ => $gjoseqlib::genetic_code{ $_ } }
    keys %gjoseqlib::genetic_code;
  
  foreach ( $self->{ 'cgi' }->param('code_opts') ) {
    my ( $codon, $aa ) = split /\./;
    $gencode{ $codon } = $aa;
  }


  #---------------------------------------------------------------------------
  #  Npre and Npost
  #---------------------------------------------------------------------------

  my $npre  = $self->{ 'cgi' }->param('npre');    # Must be defined for start and ignore
  # locations to be mapped
  $npre = $extra if ! defined( $npre );

  #---------------------------------------------------------------------------
  #  Determine downstream sequence
  #---------------------------------------------------------------------------
  
  my $npost = $self->{ 'cgi' }->param('npost');
  $npost = $extra if ! defined( $npost );

  my $proposeinframe = '';
  if ( $self->{ 'genome' } && $self->{ 'organism' } && ( $self->{ 'location' } || $self->{ 'covering' } ) ) {
    ( $proposeinframe ) = $self->propose_in_frame( \%is_start, \%gencode, $npre, $npost );
  }
  else {
    $error = $self->{ 'cgi' }->h2( 'Script requires a genome and a location' );
  }

  my $success = $self->get_function_tabview( \%is_start, \%gencode, $npre, $npost );
  my $actions = $self->get_action_buttons();
  my $legend = $self->create_legend();

  my $tab_view_component = $self->application->component( 'functionTabView' );

  ################
  # Content here #
  ################
  
  my $content = $self->{ 'cgi' }->title( 'Propose New Protein Encoding Gene' );

  if ( defined( $error ) && $error ne '' ) {
    $self->application->add_message( 'warning', $error );
  }
  else {  
    $content .= $self->{ 'cgi' }->h2( "Propose a New Protein Encoding Gene"
			  . ( ( $self->{ 'covering' } && ! $self->{ 'location' } ) ? " Covering a Region" : "" )
			  . " in the Genome<BR />".$self->{ 'organism' }." (".$self->{ 'genome' }.")" );
    
    $content .= $self->start_form( 'propose_new_png' );
    
    $content .= $tab_view_component->output();
    $content .= "<BR />";
    $content .= $actions;
    $content .= "<BR />";
    $content .= $legend;
    $content .= $proposeinframe;
    $content .= $actions;
    
    $content .= $self->end_form;
  }

  return $content;
}


#==============================================================================
#  Propose a peg that covers a region in a given frame:
#==============================================================================

sub get_function_tabview {
  
  my ( $self, $isstart, $gencode, $npre, $npost ) = @_;

  my $function = $self->{ 'cgi' }->param('function') || '';

  my $editstartcodons = $self->edit_allowed_starts( $isstart );
  my $editgeneticcode = $self->edit_genetic_code( $gencode );
  my $editfunctiontab = $self->edit_function_tab( $function, $npre, $npost );


  my $tab_view_component = $self->application->component( 'functionTabView' );
  $tab_view_component->width( 880 );
#  if ( $can_alter ) {
  $tab_view_component->add_tab( '<H2>&nbsp; Edit Function &nbsp;</H2>', "$editfunctiontab" );
#  }
  $tab_view_component->add_tab( '<H2>&nbsp; Edit Allowed Start Codons &nbsp;</H2>', "$editstartcodons" );
  $tab_view_component->add_tab( '<H2>&nbsp; Edit Genetic Code &nbsp;</H2>', "$editgeneticcode" );

  return 1;
}

sub propose_in_frame {
  my ( $self, $isstart, $gen_code, $npre, $npost ) = @_;
  
  my $application = $self->application();

  my %is_start = %$isstart;
  my %gencode = %$gen_code;

  my $html = '';
  
  #---------------------------------------------------------------------------
  #  Interpret the location information:
  #---------------------------------------------------------------------------
  
  my ( $contig, $n1, $n2, $dir, $len, $clen );
  my $ttl = 0;
  my @loc;
  my $loc = $self->{ 'location' } || $self->{ 'covering' };
  foreach ( split /,/, $loc ) {
    my ( $contig, $n1, $n2 ) = $_ =~ /^(.*)_(\d+)_(\d+)$/;
    my $clen = $self->{ 'fig' }->contig_ln( $self->{ 'genome' }, $contig );

    if ( $contig && $n1 && $n2 && $clen ) {
      $dir = ( $n2 >= $n1 ) ? +1 : -1;
      $len = ( $n2>$n1 ? $n2-$n1 : $n1-$n2 ) + 1;
      $ttl += $len;
      push @loc, [ $contig, $n1, $n2, $dir, $len, $clen ];
    }
    else {
      $html .= $self->{ 'cgi' }->h2( "Bad location in genome ".$self->{ 'genome' }.": $loc\n" );
      return $html;
    }
  }

  if ( ( $ttl % 3 ) != 0 ) {
    $html .= $self->{ 'cgi' }->h2( "Location in genome ".$self->{ 'genome' }." is not an even number of codons: $loc" );
    return $html;
  }

  #---------------------------------------------------------------------------
  #  Build a description of the DNA context to be displayed.  The elements of
  #  the description are in the form:
  #
  #     [ $contig, $n1, $n2, $dir, $len, $clen ]
  #---------------------------------------------------------------------------
  
  my @loc2 = @loc;                    # Location of DNA to show
  
  #---------------------------------------------------------------------------
  #  Determine upstream sequence
  #---------------------------------------------------------------------------
  #  This might run off end of contig.  We really want to remember if we did
  #  so, and provide user feedback, and the chance to initiate at the first
  #  triplet displayed (this last point is handled through p1_contig_end).
  
  ( $contig, $n1, $n2, $dir, $len, $clen ) = @{ $loc2[0]} ;
  my ( $p1, $p1_contig_end );

  if ( $dir > 0 ) {
    $npre  = $n1 - 1 if $npre >= $n1;  # Truncate to fit
    $npre -= $npre % 3;                # Make it a multiple of 3
    $p1    = $n1 - $npre;              # Start of displayed DNA
    $p1_contig_end = 1 if $p1 <= 3;    # Reach contig end?
  }
  else {
    $npre  = $clen - $n1  if $n1 + $npre > $clen;  # Truncate to fit
    $npre -= $npre % 3;                # Make it a multiple of 3
    $p1    = $n1 + $npre;              # Start of displayed DNA
    $p1_contig_end = 1 if $p1+3 > $clen;  # Reach contig end?
  }
  $loc2[0]->[1]  = $p1;
  $loc2[0]->[4] += $npre;
  
  #---------------------------------------------------------------------------
  #  Determine downstream sequence
  #---------------------------------------------------------------------------
  
  ( $contig, $n1, $n2, $dir, $len, $clen ) = @{$loc2[-1]};
  my $p2;
  if ( $dir > 0 ) {
    $npost  = $clen - $n2  if $n2 + $npost > $clen;  # Truncate to fit
    $npost -= $npost % 3;           # Make it a multiple of 3
    $p2     = $n2 + $npost;
  }
  else {  # July 24, 06, fix truncation location error -- GJO 
    $npost  = $n2 - 1 if $npost >= $n2;  # Truncate to fit
    $npost -= $npost % 3;           # Make it a multiple of 3
    $p2     = $n2 - $npost;
  }
  $loc2[-1]->[2]  = $p2;
  $loc2[-1]->[4] += $npost;
  
  #---------------------------------------------------------------------------
  #  We have a window to look at, let's put things in it
  #---------------------------------------------------------------------------
  #  The following two parameters are based on triplet numbering relative to
  #  the DNA region displayed.  Because the user can reset the amount of DNA
  #  prefixed, the numbers might shift.  We will require that the previous
  #  prefix length be defined for them to be used:
  #
  #  We need the number of displayed triplets to know if an old locations
  #  falls outside of the new window
  
  my $c1 =       $npre / 3;  # Prefixed triplets
  my $c2 = $c1 + $ttl  / 3;  # Triplets in prefix and requested region
  my $c3 = $c2 + $npost/ 3;  # Total triplets displayed
  
  $self->{ 'start' } = undef;
  my %ignore = ();
  
  my $old_pre = $self->{ 'cgi' }->param('old_pre');
  if ( defined( $old_pre ) ) {
      my $offset  = ( $npre - $old_pre ) / 3;
      
      #  What is the currently selected start (zero = undefined)?
      
      if ( $self->{ 'cgi' }->param( 'start' ) ) {
	$self->{ 'start' } = $self->{ 'cgi' }->param('start') + $offset;
	$self->{ 'start' } = undef if ( $self->{ 'start' } <= 0 ) || ( $self->{ 'start' } > $c3 );
      }
      
      #  Which stop codons are marked to be ignored?
      
      my $new;
      %ignore = map { $new = $_ + $offset;
		      ( $new > 0 && $new <= $c3 )? ( $new => 1 ) : ()
		    }
	$self->{ 'cgi' }->param('ignore');
    }
  $self->{ 'cgi' }->delete('old_pre');  # Annoying feature in cgi: old values are
  # sticky unless explicitly deleted.
  
  #---------------------------------------------------------------------------
  #  Is there a proposed function
  #---------------------------------------------------------------------------
  
  my $function = $self->{ 'cgi' }->param('function') || '';
  
  #  Let assign_from override the function
  
  my $assign_from = $self->{ 'cgi' }->param('assign_from') || '';
  if ( $assign_from ) {
    my $tmp_func = $self->{ 'fig' }->function_of( $assign_from, $self->{ 'seeduser' } );
    $function = $tmp_func if $tmp_func;
  }
  
  #  And of course the text box overrides the function.  We might want to
  #  change the order of these two operations.  Which takes precidence, the
  #  text box or the radio button?  Currently the text box has the last say.
  
  my $newfunction = $self->{ 'cgi' }->param('newfunction');
  if ( defined( $newfunction ) && $newfunction ) {
    $newfunction =~ s/^\s+//;
    $newfunction =~ s/\s+$//;
    $newfunction =~ s/\s+/ /g;
    $function = $newfunction;
    $self->{ 'cgi' }->delete('newfunction');  #  Sigh.  The box contents are sticky
    print STDERR $function ." HERE NOW!\n";
  }
  
  #---------------------------------------------------------------------------
  #  Does the user think that he/she/it is ready to create a feature?
  #---------------------------------------------------------------------------
  
  my $create = $self->{ 'cgi' }->param( 'create' ) || undef;
  my $replace = $self->{ 'cgi' }->param( 'replace' ) || undef;
  
  #---------------------------------------------------------------------------
  #  Most or all of the incoming state information has been examined
  #  It is time to put together the page.
  #---------------------------------------------------------------------------
  #  Put the displayed information in a FORM.  For unclear reasons I have been
  #  getting killed by state information in $cgi.  I have finally resorted
  #  to explicitly writing my own hidden input tags.  (Later note:  this is
    #  almost certainly do to my failure to properly use the library -override
  #  flag.)
 
 
#  $html .=  $cgi->start_form( -method => 'post',
#			      -action => 'propose_new_peg.cgi',
#			      -name   => 'propose_new_peg'
#			    );
  $html .= hidden_input( 'genome', $self->{ 'genome' } );
  $html .= hidden_input( 'function', $function );
  $html .= hidden_input( 'old_pre', $npre );

  if ( defined( $self->{ 'location' } ) ) {
    $html .= hidden_input( 'location', $self->{ 'location' } );
  }
  if ( defined( $self->{ 'covering' } ) ) {
    $html .= hidden_input( 'covering', $self->{ 'covering' } );
  }
  if ( defined( $self->{ 'old_peg' } ) ) {
    $html .= hidden_input( 'fid', $self->{ 'old_peg' } )
  }
  
  my $dna = $self->{ 'fig' }->dna_seq( $self->{ 'genome' }, map { join '_', $_->[0], $_->[1], $_->[2] } @loc2 );

  #---------------------------------------------------------------------------
  #  Now that the preliminaries are done, what did the user want?
  #---------------------------------------------------------------------------

  if ( $create || $replace ) {
    if ( !$self->{ 'start' } ) {
      $html .= $self->{ 'cgi' }->h3( "<FONT Color=red>Creating a feature requires defining a start site. Please select one below and try again.</FONT>" ). "\n";
      $create = undef;
      $replace = undef;
    }
    if ( ! $self->{ 'seeduser' } ) {
      $html .= $self->{ 'cgi' }->h3( "<FONT Color=red>Creating a feature requires a user ID.  "
			 . "Please enter one below and try again.</FONT>" ). "\n";
      $html .= "User ID: ";
      $html .= $self->{ 'cgi' }->textfield( -name => 'user', -size => 40 ). "<BR />\n";
      $create = undef;
      $replace = undef;
    }
    if ( ! $function ) {
      $html .= $self->{ 'cgi' }->h3( "<FONT Color=red>Creating a feature requires a defined "
                         . "function.  Please enter one below and try again.</FONT>"
		       ). "\n";
      $create = undef;
      $replace = undef;
    }

    #  Did we survive the tests?
    
    if ( $create ) {
      #  Do something exciting and intelligent.
      #
      #  Remember, there is nothing that forces the viewed region to,
      #  which is all that is in the sequences above, to include the
      #  stop codon!  We may need to search for it. 
      
      my ( $fid, $message ) = $self->create_feature( \@loc2, $dna, \%ignore, \%gencode, \%is_start, $function );
      
      if ( $fid ) {
	my $peg_link = $self->fid_link( $fid );
	$peg_link = "<A HREF='$peg_link' target=_blank>$fid</A>";

	$html .= $self->{ 'cgi' }->h3( "<FONT Color=#A00000>Request for new feature was successful: $peg_link</FONT>" );
	$self->{ 'start' } = undef;  #  Don't make it easy to create it twice. 
      }
      else {
	$html .= $self->{ 'cgi' }->h3( "<FONT Color=#A00000>Request for new feature failed:<BR>$message</FONT>" );
      }	
      $html .= "\n";
    }
    if ( $replace ) {
      #  Do something exciting and intelligent.
      #
      #  Remember, there is nothing that forces the viewed region to,
      #  which is all that is in the sequences above, to include the
      #  stop codon!  We may need to search for it. 
      
      my ( $fid, $message ) = $self->create_feature( \@loc2, $dna, \%ignore, \%gencode, \%is_start, $function );
      
      if ( $fid ) {
	my $peg_link = $self->fid_link( $fid );
	$peg_link = "<A HREF='$peg_link' target=_blank>$fid</A>";

	$html .= $self->{ 'cgi' }->h3( "<FONT Color=#A00000>Request for new feature was successful: $peg_link</FONT>" );
	$self->{ 'start' } = undef;  #  Don't make it easy to create it twice.
	
	# now remove the old peg
	my $oldpeg = $self->{ 'old_peg' };
	$self->{ 'fig' }->delete_feature( $self->{ 'seeduser' }, $oldpeg );
	$html .= $self->{ 'cgi' }->h3( "<FONT Color=#A00000>Deleted peg $oldpeg (Changing start means replacing features).</FONT>" );
      }
      else {
	$html .= $self->{ 'cgi' }->h3( "<FONT Color=#A00000>Request for new feature failed:<BR>$message</FONT>" );
      }	
      $html .= "\n";
    }
  }

    #---------------------------------------------------------------------------
    #  Blast proposed sequence against compete genomes?
    #---------------------------------------------------------------------------

  my ( $depth, $matches );
  if ( defined( $self->{ 'blastp' } ) && defined( $self->{ 'start' } ) && $self->{ 'blastp' } && $self->{ 'start' } ) {
    my $text = '';
    ( $depth, $matches, $text ) = $self->blast_orf_region( $application, $dna, \%ignore, \%gencode, $c3 );
    $html .= $text;
  }
  elsif ( defined( $self->{ 'blastp' } ) && $self->{ 'blastp' } ) {    
    $html .= $self->{ 'cgi' }->h3( '<font color=red>BLASTP analysis requires '
		       . 'selecting a start site</font>'
		     ). "\n";
  }
  
  #---------------------------------------------------------------------------
  #  What are the locations of existing features in the window?
  #---------------------------------------------------------------------------
  
  my @f_map = $self->feature_map( \@loc2 );
  
  #---------------------------------------------------------------------------
  #  What Shine-Dalgarno sites?
  #---------------------------------------------------------------------------
  
  my @sd_map = shine_dalgano_map( $dna );
  
  #---------------------------------------------------------------------------
  #  Nucleotide triplets and their attributes
  #---------------------------------------------------------------------------
  
    my $c_num = 0;

    my @dna2 = map { my $clr = shift @$_;               # Put into table cells
                     "\t<TD" . ( $clr ? " BgColor=$clr" : "" ) . ">"
                   . join( "<BR />", @$_ )
                   . "</TD>\n"
                   }
               map { $c_num++;                          # Translate and decorate them
                     my $cdn = uc $_;
                     my $aa  = $gencode{ $cdn } || 'X';
                     my $typ = "";
		     if ( defined( $aa ) && ( $aa eq "*" ) ) {
		       $typ = "-";
		     }
		     elsif ( defined( $cdn ) && defined( $is_start{ $cdn } ) ) {
		       $typ = "+";
		     }
		     elsif ( defined( $c_num ) ) {
		       if ( $c_num == 1 && defined( $p1_contig_end ) ) {
			 $typ = "+";
		       }
		       elsif ( defined( $c1 ) && $c_num <= $c1 ) {
			 $typ = ".";
		       }
		       elsif ( defined( $c1 ) && $c_num > $c2 ) {
			 $typ = ".";
		       }
		     }
		     { no warnings 'uninitialized';
		       my @cvr = $depth ? @{ shift @$depth } : ();
		       my $clr = $typ eq "-" ? "#FF8888"  #  Red stops
			 : $typ eq "+" ? "#88FF88"  #  Green starts
			   : ( $cvr[0] ne '.' && $cvr[0] > 0 ) ? "#FFFF66"  #  Yellow for matches
                             : $typ eq "." ? "#DDDDDD"  #  Gray outside of focus
			       :               '#FFFFFF'; #  White in match region
		       $clr = blend( $clr, '#0080FF', ( 0.75 * shift @sd_map ) );
		       my $ctl = $typ eq "-" ? ignore_box( $c_num, \%ignore )
			 : $typ eq "+" ? start_button( $c_num, $self->{ 'start' } )
			   :               "&nbsp;";
		       [ $clr, @cvr, $aa, $_, (shift @f_map), $ctl ]
		     }
                   }
               $dna =~ m/.../g;                      #  Break DNA into triplets

  #---------------------------------------------------------------------------
  #  Display the sequence in a table
  #---------------------------------------------------------------------------
  #  Describe the controls in the table

  $html .= "<P />Click a radio button to <b>select</b> a protein start location ";
  $html .= "(edit allowed start codons below).<BR />\n";
  $html .= "The first stop codon in that frame is selected by default. ";
  $html .= "Click a checkbox to <b>ignore</b> that stop codon (or edit the genetic code below).<P />\n";

    #  In the case of BLAST results, the extra information should be explained

  if ( $depth ) {

        $html .= <<'DEPTH_TEXT';
The two numbers above the amino acids are a site-by-site summary of the BLASTP
results.  The top value is the number of blast matches overlapping the amino
acid (nonzero values are yellow).  The bottom value is the number of blast
matches that WOULD overlap the triplet IF the match continued without gaps to
the end of the database sequence.  Blue shading indicates potential ribosome
binding sites.<P />
DEPTH_TEXT
      }

  my $ncol = 30;
  $html .= start_button( 0, -1 );
  $html .= " Cancel start selection\n";
  $html .= "<TABLE Style='font-family: Courier, monospace'>\n";

  for ( my $i0 = 0; $i0 < @dna2; $i0 += $ncol ) {
    $html .= "  <TR Align=center VAlign=top>\n";
    { no warnings 'uninitialized';
 	$html .= join( "", @dna2[$i0 .. ($i0 + $ncol - 1)] );
    }
    $html .= "  </TR>\n";
  }
  
  $html .= "</TABLE>\n";
  $html .= start_button( 0, -1 );
  $html .= " Cancel start selection<P />\n";

  return ( $html );
}


#-------------------------------------------------------------------------------
#  Some helper functions
#-------------------------------------------------------------------------------
#  Produce an HTML hidden input tag:
#-------------------------------------------------------------------------------
sub hidden_input
{   my ( $name, $value ) = @_;
    $name ? "<INPUT Type=hidden Name=" . quoted_value( $name )
            . ( defined( $value ) ? " Value=" . quoted_value( $value ) : "" )
            . ">"
          : wantarray ? () : ""
}

#-------------------------------------------------------------------------------
#  Make quoted strings for use in HTML tags:
#-------------------------------------------------------------------------------
sub quoted_value
{   my $val = shift;
    $val =~ s/\&/&amp;/g;
    $val =~ s/"/&quot;/g;
    qq("$val")
}

#-------------------------------------------------------------------------------
#  Quote HTML text so that it displays correctly:
#-------------------------------------------------------------------------------
sub html_esc
{   my $val = shift;
    $val =~ s/\&/&amp;/g;
    $val =~ s/\</&lt;/g;
    $val =~ s/\>/&gt;/g;
    $val
}

#-------------------------------------------------------------------------------
#  Build the text for an ignore stop codon checkbox
#-------------------------------------------------------------------------------
sub ignore_box
{  my ( $c_num, $ignore ) = @_;
     "<input type=checkbox name=ignore value=$c_num"
   . ( $ignore->{ $c_num } ? " checked='checked'" : "" )
   . ">"
}

#-------------------------------------------------------------------------------
#  Build the text for an start codon selection button
#-------------------------------------------------------------------------------
sub start_button {
  my ( $c_num, $start ) = @_;

  my $return = "<input type=radio name=start value=$c_num";
  if ( defined( $c_num ) && defined( $start ) && $c_num == $start ) {
    $return .= " checked='checked'";
  }
  $return .= ">";
}


#==============================================================================
#  Create a new feature
#
#  $fid = create_feature( $loc2, $dna, $start,
#                         $ignore, $gencode, $is_start, $function
#                       )
#==============================================================================

sub create_feature {
    my ( $self, $loc2, $dna, $ignore, $gencode, $is_start, $function ) = @_;

    #---------------------------------------------------------------------------
    #  The start codon becomes a methionine?
    #---------------------------------------------------------------------------

    my $nt1 = 3 * ( $self->{ 'start' } - 1 );          # Zero-based numbering into $dna
    my $init = uc substr( $dna, $nt1, 3 );
    my @pep = ( $is_start->{ $init } ? "M" : $gencode->{ $init } || 'X' );

    #---------------------------------------------------------------------------
    #  We divide the rest of the DNA into triplets and translate to a stop:
    #---------------------------------------------------------------------------

    $dna = substr( $dna, $nt1+3 );
    my $c_num = $self->{ 'start' } + 1;    #  We need triplet numbers for %ignore
    my $done = 0;              #  Flag for stop found (we could run out of DNA)

    foreach ( map { $gencode->{ uc $_ } || 'X' } $dna =~ m/.../g )  #  Translate
    {
        if    ( $_ ne "*" )           { push @pep, $_ }      #  Amino acid
        elsif ( $ignore->{ $c_num } ) { push @pep, "X" }     #  Ingnored stop
        else                          { $done = 1; last }    #  Stop
        $c_num++;                                            #  Count triplets
    }

    #---------------------------------------------------------------------------
    #  Did we run out of triplets without a stop?
    #---------------------------------------------------------------------------

    if ( ! $done ) {
        #  Is there more DNA sequence available?

        my ( $contig, $n1, $n2, $dir, $len, $clen ) = @{ $loc2->[-1] };
        my $n3 = $n2;

        while ( ! $done ) {
            my $newdna = "";
            my $dn = 900;                             # Get 900 more nucleotides

            if ( $dir > 0 )
            {
                $dn  = $clen - $n3 if ( $n3 + $dn ) > $clen;  #  Truncate if too long
                $dn -= $dn % 3;                               #  Make even triplets
                if ( $dn < 3 ) { $done = 1; last }            #  Is there any?
                $newdna = $self->{ 'fig' }->dna_seq( $self->{ 'genome' }, ( join '_', $contig, $n3+1, $n3+$dn ) );
                $n3 += $dn;
            }
            else
            {
                $dn  = $n3 - 1 if $dn >= $n3;         # Truncate if too long
                $dn -= $dn % 3;                       # Make even triplets
                if ( $dn < 3 ) { $done = 1; last }    # Is there any?
                $newdna = $self->{ 'fig' }->dna_seq( $self->{ 'genome' }, ( join '_', $contig, $n3-1, $n3-$dn ) );
                $n3 -= $dn;
            }

            foreach ( map { $gencode->{ uc $_ } || 'X' } $newdna =~ m/.../g )  # Translate
            {
                if ( $_ ne "*" ) { push @pep, $_ }       # Add to peptide
                else             { $done = 1; last }     # Stop
            }
        }
    }

    my $pep_seq = join( "", @pep );

    #---------------------------------------------------------------------------
    #  We have found the protein end.  Time to build the location description:
    #  @$loc2 is the description of the DNA from which the region is extracted.
    #---------------------------------------------------------------------------

    my $nt2 = $nt1 + 3 * length( $pep_seq ) - 1;
    my @raw = @$loc2;
    my @loc = ();
    my ( $contig, $n1, $n2, $dir, $len, $clen );
    my ( $n_min, $n_max, $p1, $p2 );

    # $n_max is the highest coordinate in $dna covered so far

    $n_max = 0;
    while ( $n_max <= $nt1 )
    {
        ( $contig, $n1, $n2, $dir, $len, $clen ) = @{ shift @raw };
        return undef if ! $contig;
        $n_min  = $n_max;
        $n_max += $len;
    }
    $p1 = $n1 + $dir * ( $nt1 - $n_min );

    while ( $n_max <= $nt2 )
    {
        push @loc, join( '_', $contig, $p1, $n2 );
        ( $contig, $n1, $n2, $dir, $len, $clen ) = @{ shift @raw };
        return undef if ! $contig;
        $p1 = $n1;
        $n_min  = $n_max;
        $n_max += $len;
    }

    $p2 = $n1 + $dir * ( $nt2 - $n_min );

    #  The terminator codon is a special case.  It was not added above because
    #  we don't want to fail if we cannot get it.  (An alternative, perhaps
    #  simpler, strategy would have been to push the terminator on the peptide,
    #  then cut it off after computing the length of the coding region.)

    if ( $dir > 0 ) { $p2 += 3 if $p2 + 3 <= $clen }
    else            { $p2 -= 3 if $p2     >  3     }

    push @loc, join( '_', $contig, $p1, $p2 );
    my $location = join ',', @loc;

    #  We now have the location description.
    #
    #  We should never recreate an existing feature.  Locate features that
    #  overlap the end of this one:

    my ( $c, $beg, $end ) = $loc[-1] =~ m/^(.+)_(\d+)_(\d+)$/;
    if ( $beg > $end )  { ( $beg, $end ) = ( $end, $beg ) }

    #  The discarded return values are min_coord and max_coord of features:

    my ( $features, undef, undef ) = $self->{ 'fig' }->genes_in_region( $self->{ 'genome' }, $c, $beg, $end );

    #  Filter by type and locate the overlapping features:

    my @feat_and_loc = map  { [ $_, scalar $self->{ 'fig' }->feature_location( $_ ) ] }
                       grep { /\.peg\.\d+$/ }          # Same type
                       @$features;                     # Overlapping features

    my @same_loc = map  { $_->[0] }                    # Save the fid
                   grep { $_->[1] eq $location }       # Same location?
                   @feat_and_loc;                      # Located features

    if ( @same_loc ) {
      my $peg_link = $self->fid_link( $same_loc[0] );
      $peg_link = "<A HREF='$peg_link' target=_blank>".$same_loc[0]."</A>";

      my $message = "<H3><FONT Color=red>This feature already exists: $peg_link</FONT></H3>\n";
      return ( undef, $message );
    }

    #  Is the proposed feature the same except for the start location?  Find
    #  out by setting first segment start to 0 (this does not handle locations
    #  that add or remove whole segments -- this behavior that might be good
    #  for alternative slicing, but it makes fixing frameshifts more tedious):

    my $loc0 = zero_start( $location );
    my @same_but_start = map  { $_->[0] }                        # Save the fid
                         grep { zero_start( $_->[1] ) eq $loc0 } # Same ending?
                         @feat_and_loc;                          # Located features

    my $change_start = $self->{ 'cgi' }->param( 'change_start' ) || undef;

    if ( ! $change_start && @same_but_start && !defined( $self->{ 'old_peg' } ) ) {
      my $message = "<H3><FONT Color=red>This request differs only in start location from ";
      $message .= "one or more existing feature(s): ";
      $message .= join( ' &amp; ', map { HTML::fid_link( $self->{ 'cgi' }, $_ ) } @same_but_start );
      $message .= "<BR />\nTo create the new feature, ";
      $message .= "choose a radio button below and click 'create' again.</FONT></H3>\n";
      $message .= "<INPUT Type=radio Name=change_start Value=keep_both> Keep both features<BR />\n";
      $message .= "<INPUT Type=radio Name=change_start Value=replace> Replace existing feature(s)<BR />\n";
      return ( undef, $message );
    }

    #---------------------------------------------------------------------------
    #  We have everything that we need to create a peg.
    #---------------------------------------------------------------------------

    my $aliases = '';
    my $fid = $self->{ 'fig' }->add_feature( $self->{ 'seeduser' }, $self->{ 'genome' }, 'peg', $location, $aliases, $pep_seq );
    if ( ! $fid ) {
      my $message = "<H3><FONT Color=red>Call to add_feature failed.  More information might be available in the WWW server log file.</FONT></H3>\n";
      return ( undef, $message );
    }

    if ( ! $self->{ 'fig' }->assign_function( $fid, ( $self->{ 'seeduser' } =~ m/^master/i ? "master" : $self->{ 'seeduser' } ), $function ) ) {
      my $message = "<H3><FONT Color=red>Call to assign_function failed.  More information might be available in the WWW server log file.</FONT></H3>\n";
      return ( undef, $message );
    }

    #  The new feature was successfully created.  Was there a request to remove
    #  one or more overlapping features?

    my $message = undef;
    if ( @same_but_start && ( $change_start =~ m/^replace$/i ) ) {
      foreach my $old_fid ( @same_but_start ) {
	$self->{ 'fig' }->delete_feature( $self->{ 'seeduser' }, $old_fid );
	$message .= "<H3><FONT Color=#A00000>Deleted feature $old_fid</FONT></H3>\n";
      }
    }
    
    return ( $fid, $message );
}


sub zero_start
{
    my @loc = split /,/, shift;
    $loc[0] =~ s/_\d+_(\d+)$/_0_$1/;
    join ',', @loc
}


#===============================================================================
#  What are the features in the window?
#===============================================================================
#  The analysis is carried out segment-by-segment in multi-segment locations.
#  The maps of the segments are simply concatenated.
#
#  |------------------------------------|----------------|---...  window
#  |------------------------------------|                         first segment
#             contig_n1_n2              |----------------|        second segment
#                                          contig_n1_n2  |---...  etc.
#
#
#  Forward oriented segment ( n1 < n2, dir = 1 ):
#
#  0   b1-n1   e1-n1  e2-n1  b2-n1    len-1  coordinates in @ends
#  |     |       |      |      |        |
#  |----->>>>>>>>>------<<<<<<<<--------|    features mapped on segment
#  n1    |       |      |      |        n2   segment coordinates in contig
#        b1      e1     e2     b2            2 feature locations in contig
#
#
#  Reverse oriented segment ( n1 > n2, dir = -1 ):
#
#  0   n1-b1   n1-e1  n1-e2  n1-b2    len-1  coordinates in @ends
#  |     |       |      |      |        |
#  |----->>>>>>>>>------<<<<<<<<--------|    features mapped on segment
#  n1    |       |      |      |        n2   segment coordinates in contig
#        b1      e1     e2     b2            2 feature locations in contig
#
#  So any location loc maps to: dir * ( loc - n1 ).
#-------------------------------------------------------------------------------

sub feature_map {  
  my ( $self, $loc2 ) = @_;
  my $string = "";   #  Catenate each segment to the end
  
  foreach my $segment ( @$loc2 ) {
    my ( $contig, $n1, $n2, $dir, $len ) = @$segment;
    my ( $min, $max ) = ( $dir > 0 ) ? ( $n1, $n2 ) : ( $n2, $n1 );
    my ( $features ) = $self->{ 'fig' }->genes_in_region( $self->{ 'genome' }, $contig, $min, $max );

    #  Mark the end points of features in the @ends array.  These can then
    #  be scanned sequentially to build the image.  Elements in @ends are
    #  counts of the following event types:
    #
    #     [ start_rightward, end_rightward, start_leftward, end_leftward ]

    my @ends;
    $#ends = $len - 1;   #  Force the array to cover the whole sequence
    foreach my $fid ( @$features ) {
      my ( $contig1, $beg, $end ) = $self->{ 'fig' }->boundaries_of( scalar $self->{ 'fig' }->feature_location( $fid ) );

      next if $contig1 ne $contig;
      
      my $rightward = ( $dir > 0 ) ? ( ( $beg < $end ) ? 1 : 0 )
	: ( ( $beg < $end ) ? 0 : 1 );
      my ( $s, $e ) = $rightward ? ( $beg, $end ) : ( $end, $beg );
      
      $s = $dir * ( $s - $n1 );  #  left end coordinate on map
      $e = $dir * ( $e - $n1 );  #  right end coordinate on map
      next if ( $s >= $len ) || ( $e < 0 );

      if ( $s < 0 ) { $s = 0 }
      $ends[ $s ]->[ $rightward ? 0 : 2 ]++;
      
      if ( $e >= $len ) { $e = $len -1 }
      $ends[ $e ]->[ $rightward ? 1 : 3 ]++;
    }
    
    #  Okay, the start and end events are marked.  Now for a text string.
    #  Symbols in the map:
    #     .  No feature
    #     >  Left-to-right feature
    #     <  Right-to-left feature
    #     =  Overlapping left-to-right and right-to-left features
    
    my @map = ();
    my ( $nright, $nleft ) = ( 0, 0 );
    foreach ( @ends ) {
      $_ ||= [];
      if ( defined( $_->[0] ) ) {
	$nright += $_->[0];
      }
      if ( defined( $_->[2] ) ) {
	$nleft  += $_->[2];
      }
      push @map, $nright ? ( $nleft ? "=" : ">" ) : ( $nleft ? "<" : "." );
      if ( defined( $_->[1] ) ) {
	$nright -= $_->[1];
      }
      if ( defined( $_->[3] ) ) {
	$nleft  -= $_->[3];
      }
    }
    
    $string .= join "", @map;
    last;
  }

    wantarray ? $string =~ m/.../g : [ $string =~ m/.../g ]
}


#==============================================================================
#  Blast the select orf and surrounding sequence against complete genomes
#
#  ( $depth, $matches ) = blast_orf_region( $dna, $start,
#                                           $ignore, $gencode, $c3
#                                         )
#
#  @$depth is an array of couples, [ depth_matched, depth_shadowed ].
#  The first number is the number of blast matches that include that
#  codon (the codon is in the interval m1-m2 below).  The second number
#  is the number of blast matches for which the subject sequence would
#  cover the codon IF the match were continued all the way to the ends
#  of the subject sequence (the codons in the interval p1-p2 below).
#
#  @$matches is an array of HSPs with the following fields:
#
#      [ sid sdef slen scr exp mat id q1 q2 s1  s2 ]
#
#  Some of the coordinate systems to juggle (coordinates are 1-based,
#  but the data arrays are all 0-based):
#
#                      start
#  1            p1  cdn1 | m1          m2         p2       c3
#  |------------|----|---|-|-----------|----------|--------| displayed seq
#               |    |   | |           |          |
#               |    |   |-|-----------|---|      |          selected orf
#               |    |     |           |          |
#               |    |-----=============------|   |          query & match
#               |    1     q1         q2     qlen |
#               |----------=============----------|          subject & match
#               1          s1         s2         slen
#
#  (m1,m2) = matching coord in displayed sequence = (cdn1+q1-1, cdn1+q2-1)
#  (p1,p2) = region shadowed by subject length = (cdn1+q1-s1, cdn1+q2-1+(slen-s2))
#                                              = (m1-(s1-1), m2+(slen-s2))
#
#  At each location along the displayed sequence, record 4 event types:
#
#     [ match_start, match_end, shadow_start, shadow_end ]
#
#  The depth of coverage will then be computed by scanning along the
#  finished array of events.
#==============================================================================

sub blast_orf_region {
    my ( $self, $application, $dna, $ignore, $gencode, $c3 ) = @_;

    my ( $cdn1, @seq, $pad, $aa, $c_num );
    my @aa = map { $gencode->{ uc $_ } || 'X' } $dna =~ m/.../g;

    #---------------------------------------------------------------------------
    # The blast_pad is translated unconditionally:
    #---------------------------------------------------------------------------

    $cdn1 = $self->{ 'start' } - $self->{ 'blast_pad' };
    $cdn1 = 1 if $cdn1 < 1;
    @seq = @aa[ ( $cdn1-1 ) .. ( $self->{ 'start' }-2 ) ];

    #---------------------------------------------------------------------------
    # The start codon becomes a methionine:
    #---------------------------------------------------------------------------

    push @seq, "M";

    #---------------------------------------------------------------------------
    # Next we translate to a stop, plus $blast_pad more:
    #---------------------------------------------------------------------------

    $pad = 0;
    for ( $c_num = $self->{ 'start' } + 1; ( $aa = $aa[ $c_num-1 ] ) && ( $pad < $self->{ 'blast_pad' } ); $c_num++ )
    {
        if ( $pad )
        {
            push @seq, ( ( $aa eq "*" ) && $ignore->{ $c_num } ? "X" : $aa );
            $pad++;
        }
        elsif ( $aa eq "*" )
        {
            if ( $ignore->{ $c_num } )
            {
                push @seq, "X";
            }
            else
            {
                push @seq, $aa;
                $pad++;
            }
        }
        else
        {
            push @seq, $aa;
        }
    }

    my $seq = join( "", @seq );
    my $qlen = length( $seq );

    #---------------------------------------------------------------------------
    #  Ready to put the query in a file:
    #---------------------------------------------------------------------------

    my $qid = "undefined";
    my $tmp_seq = "$FIG_Config::temp/run_blast_tmp_$$.seq";
    open( SEQ, ">$tmp_seq" ) || die "run_blast could not open $tmp_seq";
    print SEQ ">$qid\n$seq\n";
    close( SEQ );

    $ENV{"BLASTMAT"} ||= "$FIG_Config::blastmat";
    # my $blast_opt = $cgi->param( 'blast_options' ) || '';

    #---------------------------------------------------------------------------
    #  Do the BLAST and put the hits in a table
    #---------------------------------------------------------------------------

    my $matches = $self->blast_complete( $tmp_seq );
    unlink( $tmp_seq );

    my $text = $self->format_sims_table( $application, $matches, $qlen );

    #---------------------------------------------------------------------------
    #  Build a map of the match sites onto the displayed sequence
    #
    #  match = [ sid sdef slen scr exp mat id q1 q2 s1  s2 ]
    #             0    1    2   3   4   5   6  7  8  9  10
    #---------------------------------------------------------------------------

    my @events;
    $#events = $c3 - 1;
    my ( $m1, $m2, $p1, $p2, $slen, $q1, $q2, $s1, $s2 );
    foreach ( @$matches )
    {
        ( $slen, $q1, $q2, $s1, $s2 ) = ( @$_ )[ 2, 7..10 ];
        ( $m1, $m2 ) = ( $cdn1 + $q1 - 1, $cdn1 + $q2 - 1 );
        ( $p1, $p2 ) = ( $m1 - ( $s1 - 1 ), $m2 + ( $slen - $s2 ) );
        $p1 = 1   if $p1 < 1;
        $p2 = $c3 if $p2 > $c3;
        $events[ $m1-1 ]->[0]++;
        $events[ $m2-1 ]->[1]++;
        $events[ $p1-1 ]->[2]++;
        $events[ $p2-1 ]->[3]++;
    }

    #  Add the starts and report the values in element 0, subtract the ends
    #  in elements 1 and 2, and then report only element 0 (with the slice):

    my @depth = ();
    my ( $n_cov, $n_shad ) = ( 0, 0 );

    { no warnings 'uninitialized';
      foreach ( @events ) {
	$n_cov  += $_->[0];
	$n_shad += $_->[2];
	push @depth, [ $n_cov || ".", $n_shad || "." ];
	$n_cov  -= $_->[1];
	$n_shad -= $_->[3];
      }
    }

    ( \@depth, $matches, $text )
}


#==============================================================================
#  Search for a protein sequence in the complete genomes:
#
#     blast_complete( $html, $seqfile )
#
#   Returned data: [ sid sdef slen scr exp mat id q1 q2 s1  s2 ]
#   Index             0    1    2   3   4   5   6  7  8  9  10
#==============================================================================

sub blast_complete {
    my( $self, $seqfile ) = @_;
    my( $genome, @sims );

    my @blast_opt = qw( -F T -e 1e-2 -v 20 -b 20 -a 2 );  #  Only 20 per genome
    my $max_subject_hit = 2;                              #  Only  2 per subject

    @sims = ();
    foreach $genome ( $self->{ 'fig' }->genomes("complete") ) {
        my $db = "$FIG_Config::organisms/$genome/Features/peg/fasta";
        next if ( ! -s $db );
        next if ( ! verify_db( $db, "p" ) );

        my $sim;
        my %seen = ();  # Limit hits per subject sequence
        push @sims, map { ( ++$seen{ $_->[3] } > $max_subject_hit )
                                         ? ()
                                         : [ @$_[3,4,5,6,7,10,11,15,16,18,19] ]
                        }
                    blastall_hsps( 'blastp', $seqfile, $db, \@blast_opt );
    }

    @sims = sort { $b->[3] <=> $a->[3] } @sims;

    if ( @sims > 500 ) { @sims = @sims[0 .. 499] }

    return \@sims;
}


#==============================================================================
#  blastall_hsps( $prog, $input_file, $db, \@options )
#==============================================================================

sub blastall_hsps
{
    my( $prog, $input, $db, $options ) = @_;

    my $blastall = "$FIG_Config::ext_bin/blastall";
    my @args = ( '-p', $prog, '-i', $input, '-d', $db, @$options );

    my $bfh;
    my $pid = open( $bfh, "-|" );
    if ( $pid == 0 )
    {
        exec( $blastall,  @args );
        die join( " ", $blastall, @args, "failed: $!" );
    }

    gjoparseblast::blast_hsp_list( $bfh )
}


#==============================================================================
#  execute_blastall( $prog, $input_file, $db, $options )
#==============================================================================

sub execute_blastall
{
    my( $prog, $input, $db, $options ) = @_;

    my $blastall = "$FIG_Config::ext_bin/blastall";
    my @args = ( '-p', $prog, '-i', $input, '-d', $db, split(/\s+/, $options) );

    my $bfh;
    my $pid = open( $bfh, "-|" );
    if ( $pid == 0 )
    {
        exec( $blastall,  @args );
        die join( " ", $blastall, @args, "failed: $!" );
    }

    wantarray ? <$bfh> : [ <$bfh> ]
}


#==============================================================================
#  format_sims_table
#==============================================================================

sub format_sims_table{
  my ( $self, $application, $sims, $qlen ) = @_;
  
  my $simstable = $application->component( 'SimsTable' );

  my $html = '';
  
  if ( ! $sims || ! @$sims ) {
    return $self->{ 'cgi' }->h3('<FONT Color=#800000>No similarites were found</FONT>')."\n";
  }
  
  my @headings = ( { name => "Database<BR />sequence" },
		   { name => "Select<BR />function" },
		   { name => "Function" },
		   { name => 'Genome' },
		   { name => '<u>E-val</u><BR />%Ident' },
		   { name => 'DB<BR /><u>region</u><BR />len' },
		   { name => 'Query<BR /><u>region</u><BR />len' }
		 );
  
  $simstable->columns( \@headings );

  my @tab;

  foreach my $sim ( @$sims ) {
    my $fid = $sim->[0];

    next unless ( $self->{ 'fig' }->is_real_feature( $fid ) );
    my $func = html_esc( $self->{ 'fig' }->function_of( $fid, $self->{ 'seeduser' } ) || $sim->[1] || '' );

    my $peg_link = $self->fid_link( $fid );
    $peg_link = "<A HREF='$peg_link' target=_blank>$fid</A>";

    my @fields = ( $peg_link,
		( $func ? func_button_2( $fid ) : '' ),
		"$func",
		$self->{ 'fig' }->genus_species( $self->{ 'fig' }->genome_of( $fid ) ),
		sprintf( "<u>%s</u><BR />%.1f%%", $sim->[4], 100*$sim->[6]/$sim->[5] ),
		"<u>$sim->[9]-$sim->[10]</u><BR />$sim->[2]",
		"<u>$sim->[7]-$sim->[8]</u><BR />$qlen"
	      );

    push @tab, \@fields;
  }

 
  $simstable->data( \@tab );
  $simstable->items_per_page(10);
  $simstable->show_top_browse(1);
  $simstable->show_select_items_per_page(1);

  $html .= "<H2>BLAST Results</H2>";
  $html .= "<P>These are the results of blasting your selected ORF against the SEED ";
  $html .= "database. If you would like to create a gene, you can select a gene in the ";
  $html .= "BLAST table to annotate your new gene with this function. If you want to ";
  $html .= "deselect the function, click the radio button below the table.</P>";

  $html .= $simstable->output();
 
  $html .= func_button_2( '' )."Cancel the function selection above<P />\n";

  return $html;
}

#-------------------------------------------------------------------------------
#  Build the text for a role selection button
#-------------------------------------------------------------------------------

sub func_button { return "<td align=center><input type=radio name=assign_from value=$_[0]></td>" }
sub func_button_2 { return "<input type=radio name=assign_from value=$_[0]>" }


#==============================================================================
#  verify_db( $db, $type )
#==============================================================================

sub verify_db {
    my( $db, $type ) = @_;

    my $okay = 1;
    if ($type =~ /^p/i)
    {
        if ((! -s "$db.psq") || (-M "$db.psq" > -M $db))
        {
            system "$FIG_Config::ext_bin/formatdb -p T -i $db";
            $okay = -s "$db.psq";
        }
    }
    else
    {
        if ((! -s "$db.nsq") || (-M "$db.nsq" > -M $db))
        {
            system "$FIG_Config::ext_bin/formatdb -p F -i $db";
            $okay = -s "$db.nsq";
        }
    }

    $okay
}


#==============================================================================
#  Shine-Dalgarno score (RRGGRGGTGRTY)
#==============================================================================

sub shine_dalgano_map
{
    my ( $dna ) = @_;
    my $nmax = length( $dna ) - 1;
    my @sd = ( 0 ) x ($nmax/3);

    my @sd_scr_table =
    (
       { A =>  0.5, C => -5,   G =>  0.5, T => -5   },  # R
       { A =>  1,   C => -5,   G =>  1,   T => -5   },  # R
       { A => -5,   C => -5,   G =>  2,   T => -5   },  # G
       { A => -5,   C => -5,   G =>  2,   T => -5   },  # G
       { A =>  1.5, C => -5,   G =>  0.5, T => -5   },  # R
       { A => -5,   C => -5,   G =>  2,   T => -5   },  # G
       { A => -5,   C => -5,   G =>  2,   T => -5   },  # G
       { A => -5,   C => -5,   G => -5,   T =>  2   },  # T
       { A => -5,   C => -5,   G =>  2,   T => -5   },  # G
       { A =>  0.5, C => -5,   G =>  0.5, T => -5   },  # R
       { A => -5,   C => -5,   G => -5,   T =>  1   },  # T
       { A => -5,   C =>  0.5, G => -5,   T =>  0.5 }   # Y
    );

    for ( my $n = 0; $n <= $nmax; $n++ )
    {
        my ( $scr, $i1, $i2 ) = sd_score( substr( $dna, $n, 12 ), \@sd_scr_table );
        my $scr2 = ( $scr <  6.5 ) ? 0
                 : ( $scr < 14.5 ) ? 0.125 * ( $scr - 6.5 )
                 :                 1;
        if ( $scr2 > 0 )
        {
            my $imax = $i2;
            $imax = $nmax - $n if ( $imax > $nmax - $n );
            for ( my $i = $i1; $i <= $imax; $i++ )
            {
                my $ni = int( ( $n+$i ) / 3 );
                $sd[ $ni ] = $scr2 if ( $scr2 > $sd[ $ni ] );
            }
        }
    }

    wantarray ? @sd : \@sd;
}


sub sd_score
{
    my ( $seq, $sd_scr_table ) = @_;
    my @best = ( 0, undef, undef );
    my ( $scr, $scrmax, $i, $i1, $i2 );
    $i = 0;
    $i1 = undef;
    $scr = $scrmax = 0;

    foreach ( split //, uc $seq )
    {
        $scr += ( $sd_scr_table->[ $i ]->{ $_ } || 0 );
        
        if ( $scr >= $scrmax )
        {
            $scrmax = $scr;
            defined( $i1 ) or ( $i1 = $i );
            $i2 = $i;
        }
        elsif ( $scr < 0 )
        {
            if ( $scrmax > $best[0] ) { @best = ( $scrmax, $i1, $i2 ) }
            $scr = $scrmax = 0;
            $i1 = undef;
        }

        $i++;
    }
    if ( $scrmax > $best[0] ) { @best = ( $scrmax, $i1, $i2 ) }

    @best
}


sub blend {
    my ( $c1, $c2, $p ) = @_;
    $c1 =~ s/^#//;
    $c2 =~ s/^#//;
    my @c1 = map { hex $_ } $c1 =~ m/../g;
    my @c2 = map { hex $_ } $c2 =~ m/../g;
    my @c3 = map { ( 1 - $p ) * $_ + $p * ( shift @c2 ) } @c1;
    sprintf "#%02x%02x%02x", @c3
}

sub edit_allowed_starts {
  
  my ( $self, $is_start ) = @_;

  my $html = "\n<TABLE>\n";
  
  foreach my $nt1 ( qw( T C A G ) ) {         # First
    $html .= "  <TR>\n";

    foreach my $nt2 ( qw( T C A G ) ) {     # Second
      $html .= "    <TD>";
      $html .= join( "&nbsp;&nbsp;<BR />",
		     map { my $codon = $nt1 . $nt2 . $_;
			   $self->{ 'cgi' }->checkbox( -name     => 'is_start',
					   -value    => $codon,
					   -checked  => $is_start->{ $codon },
					   -label    => $codon,
					   -override => 1
					 )
			 } qw( T C A G ) 
		  );
      $html .= "</TD>\n";
    }
    $html .= "  </TR>\n";
  }

  $html .= "</TABLE>\n";
  return $html;
}





sub edit_function_tab {
  
  my ( $self, $function, $npre, $npost ) = @_;
  
  my $html = "<DIV STYLE='padding: 0px 10px 0px 10px;'><H3>Function</H3>";
  my $func = $self->{ 'function' } || undef;
  
  #---------------------------------------------------------------------------
  #  Let the user define or change the proposed function
  #---------------------------------------------------------------------------
  
  if ( defined( $function ) && $function ) {
    $html .= $self->{ 'cgi' }->h3( "Current function: ". html_esc( $function ) )."\n";
    $html .= "To change the function, enter one here:<BR /><BR />\n";
  }
  else {
    $html .= "To create a function, enter one here:<BR /><BR />\n";
  }
  $html .= $self->{ 'cgi' }->textfield( -name => 'newfunction', -size => 100, -value => $func ). "<BR /><BR />\n";
  
  if ( defined( $self->{ 'blastp' } ) && defined( $self->{ 'start' } ) && $self->{ 'blastp' } && $self->{ 'start' } ) {
    $html .= "or select one with a radio button in the blast search results\n<P />\n";
  }
  
  #---------------------------------------------------------------------------
  #  Let the user adjust the amount of DNA displayed
  #---------------------------------------------------------------------------
  
  $html .= '<H3>Up/Downstream nucleotides</H3>';
  $html .= 'Show ';
  $html .= $self->{ 'cgi' }->textfield( -name => 'npre',  -size => 4, -value => $npre, -override => 1 );
  $html .= " upstream nucleotides<BR />\n";
  $html .= 'Show ';
  $html .= $self->{ 'cgi' }->textfield( -name => 'npost', -size => 4, -value => $npost, -override => 1 );
  $html .= " downstream nucleotides<p />\n";
  $html .= "</DIV>\n";

  return $html;
}


sub edit_genetic_code {

  my ( $self, $gencode ) = @_;

  #---------------------------------------------------------------------------
  #  Edit the genetic code
  #---------------------------------------------------------------------------
  #  Originally, only known deviations from the standard code were allowed:
  #
  #  my %code_alts = ( AAA => [ qw( K N     ) ], # K
  #                    AGA => [ qw( R G S * ) ], # R
  #                    AGG => [ qw( R G S * ) ], # R
  #                    ATA => [ qw( I M     ) ], # I
  #                    CTA => [ qw( L T     ) ], # L
  #                    CTC => [ qw( L T     ) ], # L
  #                    CTG => [ qw( L S T   ) ], # L
  #                    CTT => [ qw( L T     ) ], # L
  #                    TAA => [ qw( * Q Y   ) ], # *
  #                    TAG => [ qw( * Q     ) ], # *
  #                    TGA => [ qw( * C W   ) ], # *
  #                  );
  #
  #                  @aa = @{ $code_alts{ $codon } || [ $gencode{ $codon } || 'X' ] };
  #
  
  my @aa = qw( A C D E F G H I K L M N P Q R S T V W Y * U X );
  
  my $html = "\n<TABLE>\n";
  
  foreach my $nt1 ( qw( T C A G ) ) {         # First
    $html .= "  <TR>\n";
    
    foreach my $nt2 ( qw( T C A G ) ) {     # Second      
      $html .= "    <TD>";
      $html .= join( "&nbsp;&nbsp;<BR />",
		     map { my $codon = $nt1 . $nt2 . $_;
			   my $vals = [ map { "$codon.$_" } @aa ];
			   my $lbls = { map { ( "$codon.$_", $_ ) } @aa  };
			   my $dflt = "$codon.$gencode->{$codon}";
			   "$codon => " .
                             $self->{ 'cgi' }->popup_menu( -name     => 'code_opts',
                                               -values   => $vals,
                                               -labels   => $lbls,
                                               -default  => $dflt,
                                               -override => 1
                                             )
                           } qw( T C A G )
		   );
      $html .= "</TD>\n";
    }
    $html .= "  </TR>\n";
  }
  $html .= "</TABLE>\n";

  return $html;
}


#################################
# Buttons under the spreadsheet #
#################################
sub get_action_buttons {

  my ( $self ) = @_;

  my $application = $self->application();

  #---------------------------------------------------------------------------
  #  Action buttons
  #---------------------------------------------------------------------------

  my $html = "<DIV id='controlpanel' STYLE='width: 880px;'><H3>Actions</H3>\n";
  $html .= "<TABLE><TR><TD Align=center>";
  $html .= $self->{ 'cgi' }->submit('update');
  $html .= "</TD><TD>display with current selections and parameters.";
  if ( defined( $self->{ 'blastp' } ) && defined( $self->{ 'start' } ) && $self->{ 'blastp' } && $self->{ 'start' } ) {
    $html .= ( $self->{ 'blastp' } && $self->{ 'start' } ? "  <FONT Color=#C00000>Blast results will be lost.</FONT>" : () );
  }
  $html .= "</TD></TR>\n";
  if ( $self->{ 'can_alter' } ) {
    $html .= "  <TR><TD Align=center>";
    $html .= $self->{ 'cgi' }->submit( 'blastp' );
    $html .= "</TD><TD>search the selected open reading frame (with an extra ";
    $html .= $self->{ 'cgi' }->textfield( -name => 'blast_pad', -size => 3, -value => $self->{ 'blast_pad' } );
    $html .= " triplets on each side) against completed genomes.</TD></TR>\n";
    $html .= "  <TR><TD Align=center>";
    if ( defined( $self->{ 'old_peg' } ) ) {
      $html .= $self->{ 'cgi' }->submit('replace');
    }
    else {
      $html .= $self->{ 'cgi' }->submit('create');
    }
    $html .= "</TD><TD>feature ".$self->{ 'old_peg' }." with a new feature build from the currently selected open reading frame.</TD></TR>\n";
  }

  $html .= "</TABLE></DIV>\n";

  return $html;
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

#    return "./protein.cgi?prot=$fid&user=".$self->{ 'seeduser' }."\&new_framework=0";
    return qq~./seedviewer.cgi?page=Annotation&feature=$fid&user=~.$self->{ 'seeduser' };
}

sub create_legend {

  my ( $self ) = @_;

  my $legend = "<DIV id='legends'>\n";
  $legend .= "<H3>Legend</H3>\n";
  
  my $space = "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;";
  my $radio = "<input type=radio>";
  my $check = "<input type=checkbox>";
  $legend .= "<TABLE>\n"
    . "    <TR>\n"
      . "        <TD>COLOR scheme:$space</TD>\n";
  $legend .= "        <TD Bgcolor='#60EE60'>$space</TD><TD>Start Codon$space</TD>\n"
    . "        <TD Bgcolor='#F6A0A0'>$space</TD><TD>Stop codon$space</TD>\n"
      . "        <TD Bgcolor='#AAAAFF'>$space</TD><TD>Possible RBS$space</TD>\n"
	. "    </TR>\n"
	  . "</TABLE><P />";
  $legend .= "<TABLE>\n"
    . "    <TR>\n"
      . "     <TD>Characters in a cell:$space</TD><TD>\n"
	."       <TABLE STYLE='border: 1pt solid black;'>\n";
  if ( defined( $self->{ 'blastp' } ) && $self->{ 'blastp' } ) {
    $legend .= "     <TR><TD>. / Number</TD></TR>\n";
    $legend .= "     <TR><TD>. / Number</TD></TR>\n";
  }
  $legend .= "       <TR><TD>Single Capital Letter$space</TD></TR>\n"
    . "       <TR><TD>3 Lowercase Letters$space</TD></TR>\n"
      . "        <TR><TD>... / >>> / <<<$space</TD></TR>\n"
	. "        <TR><TD>$radio / $check$space</TD></TR>\n"
	  . "    </TABLE>"
	    . "</TD><TD>"
	      ."         <TABLE>\n";
  if ( defined( $self->{ 'blastp' } ) && $self->{ 'blastp' } ) {
    $legend .= "     <TR><TD># BLAST matches overlapping the amino acid (nonzero values are yellow).</TD></TR>\n";
    $legend .= "     <TR><TD># BLAST matches that WOULD overlap the triplet IF the match continued without gaps to the end of the database sequence</TD></TR>\n";
  }
  $legend .= "    <TR><TD>--> Amino acid translation</TD></TR>\n"
    . "    <TR><TD>--> DNA Triplet</TD></TR>\n"
      . "    <TR><TD>--> Region not covered by a gene / covered by gene in direction / in other direction</TD></TR>\n"
	. "    <TR><TD>--> Select Start Codon / DEselect Stop Codon</TD></TR>\n"
	  . "        </TABLE></TD>\n"
	    . "    </TR>\n"
	      . "</TABLE><P />";
  $legend .= "</DIV>\n";

  return $legend;
}

1;
