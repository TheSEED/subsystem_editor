#!/usr/bin/perl -w

package SubsystemEditor::WebPage::SubsystemList;

    use strict;
    use Tracer;
    use warnings;
    use base qw( WebPage );

=head1 Subsystem List Page

=head2 Introduction

The subsystem list page enables the user to select a subsystem or make global changes to multiple
subsystems. It is the entry page for the subsystem editor, so all the other pages are linked
from this one.

=cut

=head2 Public Methods

=head3 init

    $slist->init();

This function registers the built-in components needed by the subsystem list. The user must be able
to log on to the application in order to use it. In addition, a user can only view his or her own
subsystems.

=cut

sub init {
    # Get the parameters.
    my ($self) = @_;
    Trace("registering...") if T(3);
    # Get the application object.
    my $application = $self->application;
    # Register the login component with the name "MyLogin".
    $application->register_component('Login', 'MyLogin');
    # Register the table component with the name "SubsystemList".
    $application->register_component('Table', 'SubsystemList');
}

=head3 output

    my $html = $slist->output();

This method produces the output for the page. All other useful methods are called by this one.

=cut

sub output {
    # Get the parameters.
    my ($self) = @_;
    # Declare the return variable.
    my $retVal = "";
    # Get the application and CGI objects.
    my $application = $self->application;
    my $cgi = $application->cgi;
    # Get our user data.  We need to know the user's name and whether or not
    # he is an administrator.
    Trace("Retrieving the user data.") if T(3);
    my ($userName, $adminFlag, $haveUser);
    my $user = $application->session()->user();
    if (! defined($user)) {
        # Here there is no user logged on.
        $userName = "";
        $adminFlag = 0;
        $haveUser = 0;
    } else {
        Trace("User object retrieved.") if T(3);
        $userName = $user->login;
        $adminFlag = $user->has_right($application, 'admin');
        $haveUser = 1;
    }
    Trace("Admin flag for \"$userName\" is '$adminFlag'.") if T(3);
    # Get the subsystem accessor object. This is our sole conduit for access
    # to the subsystem data store.
    my $mso = $application->getAppData('SubsystemObject');
    # Find out if the user submitted any changes.
    my $updating = ($cgi->param('update') ? 1 : 0);
    # Finally, we will create two sets of table rows: updatable rows
    # and read-only rows. The updatable rows will be presented first.
    my @updatableRows = ();
    my @normalRows = ();
    # Ask for a list of all of the subsystems.
    my @ssNames = $mso->GetAllSubsystems();
    # Loop through them.
    for my $ssName (sort @ssNames) {
        # Get this subsystem's object.
        my $ssObject = $mso->GetSubsystem($ssName);
        # Get its ID.
        my $ssID = $ssObject->ID;
        # Extract the name and curator.
        my $name = $ssObject->Name;
        my $curator = $ssObject->Curator;
        # Now we get the binary switches. These may be Yes/No flags
        # or checkboxes, depending on whether or not we can edit
        # the subsystem. We may also have new values coming in
        # from a previous display of this page.
        my ($nmpdrFlag, $extensible, $distributable);
        my $canEdit = ($haveUser && ($userName eq $curator || $adminFlag));
        # Find out if we can edit this subsystem.
        if ($canEdit) {
            if ($updating) {
                # Here we're updating it.
                $ssObject->SetNmpdrFlag($cgi->param("$ssID:NmpdrFlag"));
                $ssObject->SetExtensible($cgi->param("$ssID:Extensible"));
                $ssObject->SetDistributable($cgi->param("$ssID:Distributable"));
            }
            # At this point, the value in the $ssObject matches what we want
            # to display. Display the fields using checkboxes.
            $nmpdrFlag = $cgi->checkbox(-name => "$ssID:NmpdrFlag",
                                        -checked => $ssObject->NmpdrFlag,
                                        -value => 1, -label => '');
            $extensible = $cgi->checkbox(-name => "$ssID:Extensible",
                                        -checked => $ssObject->Extensible,
                                        -value => 1, -label => '');
            $distributable = $cgi->checkbox(-name => "$ssID:Distributable",
                                        -checked => $ssObject->Distributable,
                                        -value => 1, -label => '');
        } else {
            # Here we just display Yes or No. We can't update.
            $nmpdrFlag = ($ssObject->NmpdrFlag ? "Yes" : "");
            $extensible = ($ssObject->Extensible ? "Yes" : "");
            $distributable = ($ssObject->Distributable ? "Yes" : "");
        }
        # The last two values are never updatable.
        my $genomeCount = $ssObject->GenomeCount;
        my $version = $ssObject->Version;
        # Create the row.
        my $thisRow = [$name, $curator, $version, $nmpdrFlag, $extensible, $distributable, $genomeCount];
        # Push it into the appropriate list.
        if ($canEdit) {
            push @updatableRows, $thisRow;
        } else {
            push @normalRows, $thisRow;
        }
    }
    # Place the login component.
    my $login = $application->component('MyLogin');
    $retVal .= $login->output();
    # If we're updatable, create a form for the user.
    my $updatable = scalar(@updatableRows) > 0;
    if ($updatable) {
        $retVal .= $cgi->start_form(-method => 'POST', action => $cgi->url(-relative => 1));
        $retVal .= $cgi->hidden(-name => 'Page', -value => "SubsystemList");
    }
    # Build the table.
    my $table = $application->component('SubsystemList');
    # Show all items. This is necessary to get the update form to work.
    $table->items_per_page(-1);
    # Add the updatable rows followed by the normal rows.
    Trace("Adding data to the table.") if T(3);
    $table->data([@updatableRows, @normalRows]);
    # Set up the columns.
    $table->columns([ { name => 'Name' },
                      { name => 'Curator' },
                      { name => 'Version' },
                      { name => 'NMPDR' },
                      { name => 'extensible' },
                      { name => 'distributable' },
                      { name => 'Genomes' }
                      ]);
    Trace("Formatting the table.") if T(3);
    # Format the table for display.
    $retVal .= $table->output();
    # If we're updatable, add a SUBMIT button.
    if ($updatable) {
        $retVal .= $cgi->p($cgi->center($cgi->submit(-name => 'update', -value => 'SUBMIT CHANGES')));
    }
    # Close the form.
    $cgi->end_form();
    # Return the page.
    return $retVal;
}

1;
