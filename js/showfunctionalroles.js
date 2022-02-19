
function ChangeVisibility ( table_id ) {
  var values = new Array();
  values[0] = 1;
  values[1] = 1;
  values[2] = 1;
  values[3] = -1;
  values[4] = 1;

  var columnhash = new Array();

  //## this is the hidden string for role to column ##//
  var hiddenstring = document.getElementById( 'javascripthidden' ).value;
  var stuff = hiddenstring.split( '\n' );

  for ( a = 0; a < stuff.length; a++ ) {
    var splitarr = stuff[a].split( "\t" );
    columnhash[ 'show_role_' + splitarr[0] ] = parseInt( splitarr[1] );
    columnhash[ 'show_set_' + splitarr[0] ] = parseInt( splitarr[1] );
  }

  //## for the single roles ##//
  var show_fr_checks = document.getElementsByName( 'show_role' );
  for ( i = 0; i < show_fr_checks.length; i++ ) {
    var on = columnhash[ show_fr_checks[i].value ];

    if ( show_fr_checks[i].checked ) {
      values[ on ] = 1;
    }
    else {
      values[ on ] = 0;
    }
  } 
  
  //## now - more complex - subsets ##//
  var show_subset_checks = document.getElementsByName( 'show_set' );
  var collapse_subset_checks = document.getElementsByName( 'collapse_set' );
  var roletosubsethidden = document.getElementById( 'roletosubsethidden' ).value;
  var subsethash = new Array();

  var stuff2 = roletosubsethidden.split( '\n' );

  for ( a = 0; a < stuff2.length; a++ ) {
    var splitarr = stuff2[a].split( "\t" );
    if ( subsethash[ 'show_set_' + splitarr[1] ] ) {
      subsethash[ 'show_set_' + splitarr[1] ].push( splitarr[0] );
    }
    else {
      subsethash[ 'show_set_' + splitarr[1] ] = new Array( splitarr[0] );
    }
  }

  for ( i = 0; i < show_subset_checks.length; i++ ) {
    var on = columnhash[ show_subset_checks[i].value ];
    if ( show_subset_checks[i].checked ) {
      if ( collapse_subset_checks[i].checked ) {
	values[ on ] = 1;
	// turn off expansion //
	var kids = subsethash[ show_subset_checks[i].value ];
	for ( b = 0; b < kids.length; b++ ) {
	  var on2 = columnhash[ 'show_role_' + kids[b] ];
	  values[ on2 ] = 0;
	}
      }
      else {
	values[ on ] = 0;
	// turn on expansion //
	var kids = subsethash[ show_subset_checks[i].value ];
	for ( b = 0; b < kids.length; b++ ) {
	  var on2 = columnhash[ 'show_role_' + kids[b] ];
	  values[ on2 ] = 1;
	}
      }
    }
    else {
      values[ on ] = 0;
      // turn off expansion //
      var kids = subsethash[ show_subset_checks[i].value ];
      for ( b = 0; b < kids.length; b++ ) {
	var on2 = columnhash[ 'show_role_' + kids[b] ];
	values[ on2 ] = 0;
      }
    }
  }
  

  set_visible_columns( table_id, values );
}

function SubmitNewMeta ( buttonname, defaulttabvalue ) {
  if ( defaulttabvalue != 'a' ) {
    var defaulttab = document.getElementById( 'defaulttabhidden' );
    defaulttab.value = defaulttabvalue;
  }

  document.getElementById( 'buttonpressed' ).value = buttonname;

  document.getElementById( 'form' ).submit();

}

function setValueForSpreadsheetButton ( nodename, val ) {
  document.getElementById( nodename ).value = val; 
  document.getElementById( 'HIDDEN' + nodename ).value = val;
  document.body.removeChild(document.getElementById('1_buttonmenu_hm'));
}

function openSearchGeneWindow ( subsystem, nodename ) {

  document.body.removeChild(document.getElementById('1_buttonmenu_hm'));

  var stuff = nodename.split( '##-##' );
  var url = "?page=SearchGene&subsystem=" + subsystem + "&frabbk=" + stuff[0] + "&genome=" + stuff[1];

  window.open( url, 'target=_blank'  )

}

function MakeEditableLit ( ok ) {
  
  var span = document.getElementById( 'LitSpan' );
  var textspan = document.getElementById( 'TEXTSPAN' );
  var text = document.getElementById( 'SUBSYSLIT' );
  var editbutton = document.getElementById( 'EditLitButton' );
  var showbutton = document.getElementById( 'ShowLitButton' );

  if ( ok == 0 ) {
    text.style.display = 'inline';
    editbutton.style.display = 'none';
    textspan.style.display = 'inline';
    showbutton.style.display = 'inline';
  }
  else {
    text.style.display = 'none';
    editbutton.style.display = 'inline';
    showbutton.style.display = 'none';
    textspan.style.display = 'none';

    var pubs = text.value.split( ', ' );
    var linktext = new Array();
    
    for ( i=0; i<pubs.length; i++ ) {
      linktext[linktext.length] = "<a href=\"javascript:void(0)\"onclick=\"window.open('http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=retrieve&db=pubmed&list_uids=" + pubs[i] + "','height=640,width=800,scrollbars=yes,toolbar=yes,status=yes')\">" + pubs[i] + "</a>";
    }
    span.innerHTML = linktext.join( ", " );
  }
  
}
function MakeEditableWL ( ok ) {
  
  var span = document.getElementById( 'WLSpan' );
  var textspan = document.getElementById( 'AREASPAN' );
  var text = document.getElementById( 'SUBSYSWL' );
  var editbutton = document.getElementById( 'EditWLButton' );
  var showbutton = document.getElementById( 'ShowWLButton' );

  if ( ok == 0 ) {
    text.style.display = 'inline';
    editbutton.style.display = 'none';
    textspan.style.display = 'inline';
    showbutton.style.display = 'inline';
  }
  else {
    text.style.display = 'none';
    editbutton.style.display = 'inline';
    showbutton.style.display = 'none';
    textspan.style.display = 'none';

    if ( text.value ) {
      var pubs1string = text.value.split( '\n' );
      var linktext = new Array();
      var linkdef = new Array();
      var putinspan = '';
      
      for ( i=0; i<pubs1string.length; i++ ) {
	if ( pubs1string[i] ) {
	  var pubsarr = pubs1string[i].split( /\s+/ );
	  var href = pubsarr.pop();
	  var name = pubsarr.join(" ");
	  //putinspan = putinspan + pubsarr[0] + ": <a href=\"javascript:void(0)\"onclick=\"window.open('" + pubsarr[1] + "','height=640,width=800,scrollbars=yes,toolbar=yes,status=yes')\">" + pubsarr[1] + "</a><BR>";
	  putinspan = putinspan + name + ": <a href=\"javascript:void(0)\"onclick=\"window.open('" + href + "','height=640,width=800,scrollbars=yes,toolbar=yes,status=yes')\">" + href + "</a><BR>";
	}
      }
      
      span.innerHTML = putinspan;
    }
    else {
      span.innerHTML = '';
    }
  }
}

function checkAllVar ( element ) {
  var field = document.getElementsByName( element );
  var variantbox = document.getElementById( 'VarBox' );
  var variant = variantbox.value;
  for ( i = 0; i < field.length; i++ ) {
    var genomecheck = field[i].id; 
    var g = genomecheck.substr( 16 );
    var tmp = 'variant' + g;
    var thisvarbox = document.getElementById( tmp );
    var thisvar = thisvarbox.value;
    if ( thisvar == variant ) {
      field[i].checked = true ;
    }
  }
}

function checkAll ( element, second ) {
  var field = document.getElementsByName( element );
  for ( i = 0; i < field.length; i++ ) {
    if ( second ) {
      var tmp = "role##-##" + second;
      var hallo = field[i].id.indexOf( tmp );
      if ( hallo == 0 ) {
	field[i].checked = true ;
      }
    }
    else {
      field[i].checked = true ;
    }
  }
}

function checkFirst ( element )
{
  var field = document.getElementsByName( element );
  for ( i = 0; i < field.length/2; i++ ) {
    field[i].checked = true;
  }
}

function checkSecond ( element )
{
  var field = document.getElementsByName( element );
  for ( i= Math.round( field.length/2 ); i < field.length; i++ ) {
    field[i].checked = true ;
  }
}

function uncheckAll ( element, second )
{
  var field = document.getElementsByName( element );
  for ( i = 0; i < field.length; i++ ) {
    if ( second ) {
      var tmp = "role##-##" + second;
      var hallo = field[i].id.indexOf( tmp );
      if ( hallo == 0 ) {
	field[i].checked = false ;
      }
    }
    else {
      field[i].checked = false ;
    }
  }
}

function takeGenomeBack () {
   var allgenomes = document.getElementById( 'glisttochoose' );
   var allgtochoose = document.getElementById( 'glist' );

   var numoptions = allgenomes.options.length;
   for ( i=0; i<numoptions; i++ ) {
      if ( allgenomes.options[ i ].selected ) {
         allgtochoose.options[ allgtochoose.options.length ] = new Option( allgenomes.options[ i ].text, allgenomes.options[ i ].value );
         allgenomes.remove( i );
         i--;
         numoptions--;
      }
   }
}

function putGenomeIn () {
   var allgenomes = document.getElementById( 'glisttochoose' );
   var allgtochoose = document.getElementById( 'glist' );

   var numoptions = allgtochoose.options.length;
   for ( i=0; i<numoptions; i++ ) {
      if ( allgtochoose.options[ i ].selected ) {
         allgenomes.options[ allgenomes.options.length ] = new Option( allgtochoose.options[ i ].text, allgtochoose[ i ].value );
         allgtochoose.remove( i );
         i--;
         numoptions--;
      }
   }
}

function submitGS ( variablesubmit ) {

   var allgenomes = document.getElementById( 'glist' );

   var numoptions = allgenomes.options.length;
   for ( i=0; i<numoptions; i++ ) {
      allgenomes.options[ i ].selected = 1;
   }

   document.getElementById( 'actionhidden' ).value = variablesubmit;
   document.getElementById( 'form' ).submit();

}

function submitPage ( variablesubmit ) {

   document.getElementById( 'actionhidden' ).value = variablesubmit;
   document.getElementById( 'form' ).submit();

}

function putInText () {
  
  var scrollinglist = document.getElementById( 'namelist' );
  var selected = scrollinglist.options[ scrollinglist.selectedIndex ].value;

  var textfield = document.getElementById( 'LISTINPUT' );
  textfield.value = selected;
}

function OpenGenomeList ( url ) {

   var listarray = document.getElementsByName( 'add_user_set' );
   if ( listarray.length > 0 ) {
     var glist = listarray[0];
     if ( !( glist.value == 'None' ) ) {
       //   open_page( url, genomes );
       url = url + "?page=EditGenomeSelection&showlist=" + glist.value;
       window.open( url );
     }
   }
}

function AlignSeqs ( url, which ) {

  var checkarray = document.getElementsByName( 'cds_checkbox' );
  var count = 0;
  for ( i=0; i<checkarray.length; i++ ) {
    if ( checkarray[i].checked ) {
      count++;
    }
  }
  if ( count > 1 ) {
    var page = document.getElementById( 'page' );
    if ( which == 'clustal' ) {
      page.value = 'AlignSeqsClustal';
    }
    else {
      page.value = 'AlignSeqs';
    }
    document.forms.form.submit();
  }
  else {
    alert( "You need at least two sequences to form an alignment. Please check two or more sequences in the table." );
  }
}

function ShowSeqs ( url ) {

  var checkarray = document.getElementsByName( 'cds_checkbox' );
  var count = 0;
  for ( i=0; i<checkarray.length; i++ ) {
    if ( checkarray[i].checked ) {
      count++;
    }
  }
  if ( count > 0 ) {
    var page = document.getElementById( 'page' );
    page.value = 'ShowSeqs';
    document.forms.form.submit();
  }
  else {
    alert( "No sequences selected!" );
  }

}

function OpenGenesInColumn ( url, subsystem ) {

   var listarray = document.getElementsByName( 'rolelist' );
   if ( listarray.length > 0 ) {
     var fr = listarray[0];
     if ( ( fr.value ) ) {
       //   open_page( url, genomes );
       url = url + "?page=GenesForColumn&subsystem=" + subsystem + "&fr=" + fr.value;
       window.open( url );
     }
     else {
       alert ( "You have not selected a column to show" );
     }
   }
}

function OpenParalogyfier ( url, subsystem, user ) {

   var listarray = document.getElementById( 'rolelist' );
   var numoptions = listarray.options.length;
   var checkarray = document.getElementsByName( 'genome_checkbox' );
   var url = 'resolve_paralogs.cgi';
   var first = 1;
   var wasin1 = 0;
   var wasin2 = 0;

   var f = document.createElement('form');
   f.setAttribute('method', 'post', 0);
   f.setAttribute('enctype', 'multipart/form-data', 0);
   f.setAttribute('action', url, 0);
   f.setAttribute('target', '_blank', 0);
   f.setAttribute('name', 'toastform', 0);

   for ( i=0; i<numoptions; i++ ) {
     if ( listarray.options[ i ].selected ) {
       wasin1 = 1;
       var thisname = "THISROLE_" + listarray[i].value;
       var thisrole = document.getElementById( thisname );
       // if ( first ) {
// 	 url = url + "?roles=" + thisrole.value;
// 	 first = 0;
//        }
//        else {
// 	 url = url + "&roles=" + thisrole.value;
//        }
       
       var h = document.createElement('input');
       h.setAttribute('type', 'hidden', 0);
       h.setAttribute('name', 'roles', 0);
       h.setAttribute('value', thisrole.value, 0);
       f.appendChild(h);
     }
   }
   
   for ( i=0; i<checkarray.length; i++ ) {
     var check = checkarray[i];
     if ( check.checked ) {
       wasin2 = 1;
       var genomecheck = check.id; 
       var g = genomecheck.substr( 16 );
       //       url = url + "&genome=" + g;

       var h = document.createElement('input');
       h.setAttribute('type', 'hidden', 0);
       h.setAttribute('name', 'genome', 0);
       h.setAttribute('value', g, 0);
       f.appendChild(h);
     }
   }
   
   if ( !wasin1 || !wasin2 ) {
     var errormssg = '';
     if ( !wasin1 ) {
       errormssg = "No columns (roles) selected\n";
     }
     if ( !wasin2 ) {
       errormssg = errormssg + "No genomes selected\n";
     }
     alert( errormssg );
   }
   else {
     //     url = url + '&user=' + user;
     
     var h = document.createElement('input');
     h.setAttribute('type', 'hidden', 0);
     h.setAttribute('name', 'user', 0);
     h.setAttribute('value', user, 0);
     f.appendChild(h);

     document.getElementById('content').appendChild(f);
     document.forms.toastform.submit();
     document.getElementById('content').removeChild(f);
     //     window.open( url );
   }
}

function OpenMissingWithMatchesColumn ( url, subsystem, table ) {

   var listarray = document.getElementById( 'rolelist' );
   var liststring = '';
   var numoptions = listarray.options.length;

   for ( i=0; i<numoptions; i++ ) {
     if ( listarray.options[ i ].selected ) {
       liststring = liststring + '&fr=' + listarray[i].value;
     }
   }
   //   open_page( url, genomes );
   if ( !( liststring == '' ) ) {
     if ( table ) {
       url = url + "?page=MissingWithMatches&subsystem=" + subsystem + liststring;
     }
     else {
       url = url + "?page=ShowMissingWithMatches&subsystem=" + subsystem + liststring;
     }
     window.open( url );
   }
   else {
     alert ( "You have not selected a column to show" );
   }
}

function OpenMissingWithMatchesGenome( url, subsystem, table ) {
         
  var checkarray = document.getElementsByName( 'genome_checkbox' );
  var genomes = '';
  
  for ( i=0; i<checkarray.length; i++ ) {
    var check = checkarray[i];
    if ( check.checked ) {
      genomes = genomes + "&genome=" + check.value;
    }
  }
  
  //   open_page( url, genomes );
  if ( !( genomes == '' ) ) {
    if ( table ) {
      url = url + "?page=MissingWithMatches&subsystem=" + subsystem + genomes;
    }
    else {
      url = url + "?page=ShowMissingWithMatches&subsystem=" + subsystem + genomes;
    }
    window.open( url );
  }
}

function OpenRenameSubsystem( url ) {

   var checkarray = document.getElementsByName( 'subsystem_checkbox' );
   var subsystem = 0;

   for ( i=0; i<checkarray.length; i++ ) {
     var check = checkarray[i];
     if ( check.checked ) {
       subsystem = check.id;
     }
   }
   //   open_page( url, genomes );
   
   if ( subsystem ) {
     url = url + "?page=RenameSubsystem&subsystem=" + subsystem;
     window.open( url );
   }
}

function OpenGenomeSelection( url ) {

   var checkarray = document.getElementsByName( 'genome_checkbox' );
   var genomes = 0;

   for ( i=0; i<checkarray.length; i++ ) {
     var check = checkarray[i];
     if ( check.checked ) {
       if ( !genomes ) {
	 genomes = check.id;
       }
       else {
	 genomes = genomes + "~" + check.id;
       }
     }
   }
   //   open_page( url, genomes );

   if ( genomes ) {
     url = url + "?page=EditGenomeSelection&genomes=" + genomes;
     window.open( url );
   }
}

//function open_page ( url, genomes ) {
//  var http_request;
//  if (window.XMLHttpRequest) {
//    http_request = new XMLHttpRequest();
//    http_request.overrideMimeType('text/xml');
// } else if (window.ActiveXObject) {
//    http_request = new ActiveXObject("Microsoft.XMLHTTP");
//  }

// var parameters = "genomes=" + genomes;
//  parameters = parameters + "&page=EditGenomeSelection";

//  http_request.onreadystatechange = function() { write_window(http_request); };

//  http_request.open( 'POST', url, true );
//  http_request.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
//  http_request.setRequestHeader("Content-length", parameters.length);
//  http_request.setRequestHeader("Connection", "close");
//  http_request.send(parameters);
//}

//function write_window (http_request) {
//  if (http_request.readyState == 4) {
//    var win = window.open();
//    win.document.write(http_request.responseText);
//    win.document.close();
//  }
//}


function gethiddenoption() {

   var selecth1 = document.getElementById( 'SUBSYSH1' );
   var selects = document.getElementsByName( 'SUBSYSH2' );
   for ( i=0; i<selects.length; i++ ) {
      selects[i].className='hideme';
      for ( j=0; j<selects[i].options.length; j++ ) {
	selects[i].options[j].selected=0;
      }
   }

   document.getElementById( selecth1.options[selecth1.selectedIndex].value ).className='showme';

}

function radioclassification() {

   var text1 = document.getElementById( 'SUBSYSH1TF' );
   var text2 = document.getElementById( 'SUBSYSH2TF' );
   var selecth1 = document.getElementById( 'SUBSYSH1' );
   var selects = document.getElementsByName( 'SUBSYSH2' );
   var firstclasstext = '';
   
  if (selecth1.selectedIndex >= 0) {
    firstclasstext = selecth1.options[ selecth1.selectedIndex ].value;
  }

   if ( text1.disabled ) {
      text1.disabled = false;
      text2.disabled = false;
      selecth1.disabled = true;
      text1.value = firstclasstext;
   }
   else {
      text1.disabled = true;
      text2.disabled = true;
      selecth1.disabled = false;
   }
}

function SubmitGenes ( buttonname ) {

  document.getElementById( 'actionhidden' ).value = buttonname;

  document.getElementById( 'form' ).submit();

}

function SubmitManage ( buttonname, defaulttabvalue ) {

  document.getElementById( 'buttonpressed' ).value = buttonname;

  document.getElementById( 'manage' ).submit();

}

function SubmitSpreadsheet ( buttonname, defaulttabvalue ) {
  var defaulttab = document.getElementById( 'defaulttabhidden' );
  defaulttab.value = defaulttabvalue;

  var tableid = document.getElementById( 'tableid' ).value;

  document.getElementById( 'buttonpressed' ).value = buttonname;

  if ( tableid != null ) {

    if ( document.getElementById( 'table_' + tableid + '_operand_' + 2 ) ) {
      var filterOrganism = document.getElementById( 'table_' + tableid + '_operand_' + 2 ).value;
      document.getElementById( 'filterOrganism' ).value = filterOrganism;
    }
    if ( document.getElementById( 'table_' + tableid + '_operand_' + 3 ) ) {
      var filterDomain = document.getElementById( 'table_' + tableid + '_operand_' + 3 ).value;
      document.getElementById( 'filterDomain' ).value = filterDomain;
    }
  }
  
  if ( buttonname == 'SAVEEMPTYCELLS' ) {
    var ecbuttons = document.getElementsByName( 'EMPTYCELLHIDDENS' );
    for ( i=0; i<ecbuttons.length; i++ ) {

      var buttonvalue = ecbuttons[i].value;
      var fr_genome = ecbuttons[i].id;
      ecbuttons[i].value = fr_genome + '##-##' + buttonvalue;
    }
  }

  document.getElementById( 'subsys_spreadsheet' ).submit();

}

function MakeEditableVariants ( id ) {

  var editbutton = document.getElementsByName( 'EditVariants' );
  var deletebutton = document.getElementsByName( 'DeleteGenomes' );
  var showonlybutton = document.getElementsByName( 'ShowOnlyButton' );
  var savebutton = document.getElementsByName( 'SaveVariants' );

  
  for ( i=0; i<editbutton.length; i++ ) {
    editbutton[i].style.display = 'none';
    deletebutton[i].style.display = 'none';
    showonlybutton[i].style.display = 'none';
    savebutton[i].style.display = 'inline';
  }

  show_column( id, 5 );
  hide_column( id, 4 );

}

function MakeEditableFR ( id, action ) {

  var span = document.getElementById( 'span'+id );
  var text = document.getElementById( 'text'+id );
  var edit = document.getElementById( 'reedit'+id );
  var ok   = document.getElementById( 'reok'+id );

  if ( action == 0 ) {
    ok.style.display = 'inline';
    edit.style.display = 'none';
    span.style.display = 'none';
    text.style.display = 'inline';
  }
  else {
    edit.style.display = 'inline';
    ok.style.display = 'none';
    span.style.display = 'inline';
    text.style.display = 'none';
    var reactions = text.value.split( ', ' );
    var linktext = new Array();

    for ( i=0; i<reactions.length; i++ ) {
      linktext[linktext.length] = "<a href=\"javascript:void(0)\"onclick=\"window.open('http://www.genome.ad.jp/dbget-bin/www_bget?rn+" + reactions[i] + "','$&','height=640,width=800,scrollbars=yes,toolbar=yes,status=yes')\">" + reactions[i] + "</a>";
    }
    span.innerHTML = linktext.join( ", " );
  }

}

function MakeEditableReordering ( ) {

  var spanarray = document.getElementsByName( 'spanindexfr' );
  var textarray = document.getElementsByName( 'textindexfr' );
  var spanrolearray = document.getElementsByName( 'spanmerole' );
  var spanabbrarray = document.getElementsByName( 'spanmeabbr' );
  var spansubsetarray = document.getElementsByName( 'spanmesubset' );
  var frabarray = document.getElementsByName( 'FRAB' );
  var frarray = document.getElementsByName( 'FR' );
  var subsetarray = document.getElementsByName( 'SUBSETCOLUMNTEXT' );
  var showfrimagearray = document.getElementsByName( 'SHOWFRIMAGE' );

  var buttonReorder = document.getElementById( 'ReorderRoles' );
  var buttonDoReorder = document.getElementById( 'DoReorder' );
  var bottombuttons = document.getElementById( 'BOTTOMBUTTONTABLE' );
  var addroletexttr = document.getElementById( 'ADDROLETEXTTR' );
  var newroletr = document.getElementById( 'NEWROLETR' );

  buttonReorder.style.display = 'none';
  bottombuttons.style.display = 'none';
  addroletexttr.style.display = 'none';
  newroletr.style.display = 'none';
  buttonDoReorder.style.display = 'inline';
  
  for ( i=0; i<spanarray.length; i++ ) {
    spanarray[i].style.display = 'none';
    textarray[i].style.display = 'inline';
    spanrolearray[i].style.display = 'inline';
    spanabbrarray[i].style.display = 'inline';
    spansubsetarray[i].style.display = 'inline';
    frabarray[i].style.display = 'none';
    frarray[i].style.display = 'none';
    subsetarray[i].style.display = 'none';
    showfrimagearray[i].style.display = 'none';
  }
  
}

function HideWhat ( what ) {
  var showntextarray = document.getElementsByName( what + 'COLUMNTEXT' );
  var showntdarray = document.getElementsByName( what + 'COLUMN' );
  var showimage = document.getElementById( 'SHOW' + what + 'IMAGE' );
  var subsetstatus = document.getElementById( what + 'STATUS' );

  showimage.style.display = 'inline';
  subsetstatus.value = '0';

  for ( i=0; i<showntdarray.length; i++ ) {
    showntdarray[i].style.display = 'none';
  }
}


function ShowWhat ( what ) {
  var showntextarray = document.getElementsByName( what + 'COLUMNTEXT' );
  var showntdarray = document.getElementsByName( what + 'COLUMN' );
  var showimage = document.getElementById( 'SHOW' + what + 'IMAGE' );
  var subsetstatus = document.getElementById( what + 'STATUS' );

  showimage.style.display = 'none';
  subsetstatus.value = '1';

  for ( i=0; i<showntdarray.length; i++ ) {
    showntdarray[i].style.display = 'block';
  }
}
