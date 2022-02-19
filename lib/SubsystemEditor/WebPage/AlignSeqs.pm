package SubsystemEditor::WebPage::AlignSeqs;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;

use FIG;
use FIGV;
use UnvSubsys;

use base qw( WebPage );

1;

##################################################
# Method for registering components etc. for the #
# application                                    #
##################################################
sub init {
  my ( $self ) = @_;

  $self->application->register_component( 'Table', 'PegTable' );
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

  # needed objects #
  my $fig = new FIG;
  my $application = $self->application();
  my $cgi = $application->cgi;

  my $content = '<H1>Display TCoffee alignment</H1>';
  my $error = '';
  
  my $fid = $cgi->param( 'feature' );
  if ( $fid =~ /cds_checkbox_(.*)/ ) {
    $fid = $1;
  }

  my $job_id = time();
  my $temp_file = "$FIG_Config::temp/$job_id.fasta";
  if ( defined( $fid ) ) {
    open(OUT,">$temp_file");
    if ( $fid =~ /fig\|(\d+.\d+.p)eg(.\d+)/ ){
      print OUT ">$1$2\n";      
      my $fid_seq = $fig->get_translation($fid);
      print OUT "$fid_seq\n";
    }   
    elsif ( $fid =~ /fig\|(\d+.\d+.\w)\w+(.\d+)/ ) {
      print OUT ">$1$2\n";      
      my $fid_seq = $fig->get_dna_seq($fid);
      print OUT "$fid_seq\n";
    }
  }

  my $counter = 0;
  my @seqs = $cgi->param( 'cds_checkbox' );
  unless ( scalar( @seqs ) ) {
    @seqs = $cgi->param( 'fid' );
  }

  foreach my $key ( @seqs ) {
    if ( $key =~ /cds_checkbox_(.*)/ ) {
      $key = $1;
    }
    if ( !defined( $fid ) ) {
      $fid = $key;
      open(OUT,">$temp_file");
      if ( $fid =~ /fig\|(\d+.\d+.p)eg(.\d+)/ ){
	print OUT ">$1$2\n";
	my $fid_seq = $fig->get_translation($fid);
	print OUT "$fid_seq\n";
      }
      elsif ( $fid =~ /fig\|(\d+.\d+.\w)\w+(.\d+)/ ){
	print OUT ">$1$2\n";
	my $fid_seq = $fig->get_dna_seq( $fid );
	print OUT "$fid_seq\n";
      }
      next;
    }

    if ( $key =~/fig\|(\d+.\d+.p)eg(.\d+)/) {
      if ( $counter > 50 ) {
	$error .= "Alignment cutoff is currently 50 sequences. You have submitted ";
	$error .= scalar( @seqs );
	$error .= " sequences. I'm aligning the first 50 here.<BR>\n";
	last;
      }
      $counter++;
      print OUT ">$1$2\n";
      my $seq = $fig->get_translation( $key );
      print OUT "$seq\n";
    }
    else {
      if ( $key =~/fig\|(\d+.\d+.\w)\w\w(.\d+)/) {
	if ( $counter > 50 ) {
	  $error .= "Alignment cutoff is currently 50 sequences. You have submitted ";
	  $error .= scalar( @seqs );
	  $error .= " sequences. I'm aligning the first 50 here.<BR>\n";
	  last;
	}
	$counter++;
	print OUT ">$1$2\n";
	my $seq = $fig->get_dna_seq( $key );
	print OUT "$seq\n";
	
      }
    }
  }
  close(OUT);

  if ( $counter ) {
    $ENV{HOME_4_TCOFFEE} = "$FIG_Config::temp/";
    $ENV{DIR_4_TCOFFEE} = "$FIG_Config::temp/.t_coffee/";
    $ENV{CACHE_4_TCOFFEE} = "$FIG_Config::temp/cache/";
    $ENV{TMP_4_TCOFFEE} = "$FIG_Config::temp/tmp/";
    $ENV{METHOS_4_TCOFFEE} = "$FIG_Config::temp/methods/";
    $ENV{MCOFFEE_4_TCOFFEE} = "$FIG_Config::temp/mcoffee/";
    
    my @cmd = ("$FIG_Config::ext_bin/t_coffee","$temp_file", "-output", "score_html", "-outfile", "$FIG_Config::temp/$job_id.html", "-run_name", "$FIG_Config::temp/$job_id","-quiet","$FIG_Config::temp/junk.txt");
    
    my $command_string = join( " ", @cmd );
    
    open( RUN, "$command_string |" );
    while ( $_ = <RUN> ) {}
    close(RUN);
    open( HTML, "$FIG_Config::temp/$job_id.html" );
    while($_ = <HTML>){
      $_ =~s/<html>//;
      $_ =~s/<\/html>//;
      $content .= $_;
    }
  }
  else {
    $error .= "You need at least two sequences to form an alignment.<BR>\n";
  }

  ###############################
  # Display errors and comments #
  ###############################
 
  if ( defined( $error ) && $error ne '' ) {
    $self->application->add_message( 'warning', $error );
  }

  return $content;
}
