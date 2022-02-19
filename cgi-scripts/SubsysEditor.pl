use strict;
use warnings;

use FIG_Config;
use lib "$FIG_Config::fig_disk/dist/current/$FIG_Config::arch/lib/WebApplication";
use lib "$FIG_Config::common_runtime/lib/SubsystemEditor";

use WebApplication;
use WebMenu;
use WebLayout;

my $have_fcgi;
eval {
    require CGI::Fast;
    $have_fcgi = 1;
};

if ($have_fcgi && ! $ENV{REQUEST_METHOD})
{

    #
    # Precompile modules. Find where we found one, and use that path
    # to walk for the rest.
    #
    my $mod_path = $INC{"WebComponent/Ajax.pm"};
    if ($mod_path && $mod_path =~ s,WebApplication/WebComponent/Ajax\.pm$,,)
    {
	local $SIG{__WARN__} = sub {};
	for my $what (qw(SeedViewer RAST WebApplication))
	{
	    for my $which (qw(WebPage WebComponent DataHandler))
	    {
		opendir(D, "$mod_path/$what/$which") or next;
		my @x = grep { /^[^.]/ } readdir(D);
		for my $mod (@x)
		{
		    $mod =~ s/\.pm$//;
		    my $fullmod = join("::", $what, $which, $mod);
		    eval " require $fullmod; ";
		}
		closedir(D);
	    }
	}
    }

    my $max_requests = $FIG_Config::fcgi_max_requests || 50;
    my $nothing = $FIG_Config::fcgi_max_requests; # this is a hack to stop errors in the log
    my $n_requests = 0;

    warn "begin loop\n";
    while (($max_requests == 0 || $n_requests++ < $max_requests) &&
	   (my $cgi = new CGI::Fast()))
    {
	eval {
	    &main($cgi);
	};

	if ($@)
	{
	    my $error = $@;
	    Warn("Script error: $error") if T(SeedViewer => 0);
	    
	    print CGI::header();
	    print CGI::start_html();
	    
	    # print out the error
	    print '<pre>'.$error.'</pre>';
	    
	    print CGI::end_html();
	}
    }
}
else
{
    my $cgi = new CGI;
    eval {
	&main($cgi);
    };
    if ($@)
    {
	my $error = $@;
	Warn("Script error: $error") if T(SeedViewer => 0);
	
	print CGI::header();
	print CGI::start_html();
	
	# print out the error
	print '<pre>'.$error.'</pre>';
	
	print CGI::end_html();
    }
}

sub main
{
    my($cgi) = @_;

    my $layout = WebLayout->new('./Html/SubsystemEditorLayout.tmpl');
    $layout->add_css('./Html/SubsystemEditor.css');
    $layout->add_css('./Html/default.css');
    
    my $menu = WebMenu->new();
    $menu->add_category( 'Home', 'SubsysEditor.cgi?page=SubsystemOverview' );
    $menu->add_category( 'Logout', 'SubsysEditor.cgi?page=Logout', undef, [ 'login' ] );
    
    my $WebApp = WebApplication->new( { id       => 'SubsystemEditor',
					    menu     => $menu,
					    layout   => $layout,
					    default  => 'SubsystemOverview',
					    cgi => $cgi,
					} );
    
    $WebApp->show_login_user_info(1);
    $WebApp->run();
}
