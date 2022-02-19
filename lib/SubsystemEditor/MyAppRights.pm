package SubsystemEditor::MyAppRights;

1;

use strict;
use warnings;

sub rights {
	return [ [ 'login','*','*' ], [ 'view','registration_mail','*' ], [ 'view','user','*' ], [ 'add','user','*' ], [ 'delete','user','*' ], [ 'edit','user','*' ], [ 'view','scope','*' ], [ 'add','scope','*' ], [ 'delete','scope','*' ], [ 'edit','scope','*' ], [ 'view','group_request_mail','*' ], [ 'edit','subsystem','*' ], [ 'edit','subsystem','*' ], [ 'login','*','*' ], [ 'login','*','*' ], [ 'edit','subsystem','*' ], ];
}
