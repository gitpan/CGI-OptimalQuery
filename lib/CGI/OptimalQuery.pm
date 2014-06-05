package CGI::OptimalQuery;

use strict;
use warnings;
no warnings qw( uninitialized );
use CGI();

BEGIN {
    use Exporter ();
    use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
    $VERSION     = '0.08';
    @ISA         = qw(Exporter);
    #Give a hoot don't pollute, do not export more than needed by default
    @EXPORT      = qw();
    @EXPORT_OK   = qw();
    %EXPORT_TAGS = ();
}


# module registry - when loading a sub module, the module CGI param is
# consulted, and the value is loaded as a module.
my $default_module = 'InteractiveQuery';
my %modules = (
  'PrinterFriendly'   => 'CGI::OptimalQuery::PrinterFriendly',
  'CSV'               => 'CGI::OptimalQuery::CSV',
  'InteractiveFilter' => 'CGI::OptimalQuery::InteractiveFilter',
  'InteractiveQuery'  => 'CGI::OptimalQuery::InteractiveQuery2',
  'XML'               => 'CGI::OptimalQuery::XML',
  'InteractiveQuery2' => 'CGI::OptimalQuery::InteractiveQuery2',
  'InteractiveFilter2' => 'CGI::OptimalQuery::InteractiveFilter2',
  'ShowColumns'        => 'CGI::OptimalQuery::ShowColumns',
  'InteractiveQuery2Tools' => 'CGI::OptimalQuery::InteractiveQuery2Tools'
);


# Constructor
# my $recset = CGI::OptimalQuery->new(\%schema )
# This constructor instantiates the correct class based on the module param.
sub new {
  my $pack = shift;
  my $schema = $_[0];
  $$schema{q} ||= new CGI();

  # if this is a mod_perl query object, turn it into a CGI object
  if (! $$schema{q}->isa('CGI')) {
    my @names = $$schema{q}->param();
    my %params;
    foreach my $p (@names) {
      my @v = $$schema{q}->param($p);
      $params{$p} = \@v;
    }
    $$schema{q} = new CGI(\%params);
  }

  # set default handlers
  $$schema{output_handler} ||= sub { print @_ };
  $$schema{error_handler}  ||= sub { print STDERR @_; 0; };

  # find module & class
  my $module = $$schema{q}->param('module') || $$schema{module} || $default_module;
  my $class = $$schema{modules}{$module} || $modules{$module};

  # dynamically load class
  my $rv = eval "require $class";
  if ($@ =~ /Not\ Found/) { die "Could not find class $class"; } 
  elsif ($@) { die "Compile Error in class $class: $@"; } 
  elsif ($rv != 1) { die "Initialization error in class $class, should return 1"; }

  # call appropriate constructor
  return $class->new(@_);
}

sub escape_js { CGI::OptimalQuery::Base::escape_js(@_); }

sub get_saved_search_list {
  my $q = shift;
  my $dbh = shift;
  my $userid = shift;

  if ($q->param('OQ_remove_saved_search_id') =~ /^\d+$/) {
    $dbh->do("DELETE FROM oq_saved_search WHERE id = ? AND user_id = ?", undef, $q->param('OQ_remove_saved_search_id'), $userid);
  }

  my $oracleReadLen;
  if ($$dbh{Driver}{Name} eq 'Oracle') {
    ($oracleReadLen) = $dbh->selectrow_array("SELECT max(dbms_lob.getlength(params)) FROM oq_saved_search WHERE user_id = ?", undef, $userid);
  }
  local $dbh->{LongReadLen} = $oracleReadLen
    if $oracleReadLen && $oracleReadLen > $dbh->{LongReadLen};

  my $sth = $dbh->prepare("SELECT id, uri, oq_title, user_title, params FROM oq_saved_search WHERE user_id = ? ORDER BY oq_title, user_title");
  $sth->execute($userid);
  my $last_oq_title = '';
  my $buffer = '';
  while (my ($id, $uri, $oq_title, $user_title, $params) = $sth->fetchrow_array()) {
    if ($last_oq_title ne $oq_title) {
      $last_oq_title = $oq_title;
      $buffer .= "</table>" if $buffer;
      $buffer .= "<table class='OQ_ss'><tr><td colspan='2' class='OQ_ss_title'>".CGI::escapeHTML($oq_title)."</td></tr>";
    }

    my $stateArgs = '';
    if ($params ne '') {
      $params = eval '{'.$params.'}';
      if (ref($params) eq 'HASH') {
        delete $$params{show};
        delete $$params{rows_page};
        delete $$params{page};
        delete $$params{hiddenFilter};
        delete $$params{filter};
        delete $$params{queryDescr};
        delete $$params{sort};
        while (my ($k,$v) = each %$params) {
          $stateArgs .= "&amp;$k=";
          $stateArgs .= (ref($v) eq 'ARRAY') ? CGI::escape($$v[0]) : CGI::escape($v);
        }
      }
    }
    
    $buffer .= "<tr><td class='OQ_ss_query_title'><a href=# onclick=\"opwin('$uri?OQLoadSavedSearch=$id".$stateArgs."#OQtop','OQLoadSavedSearch$id','resizable,scrollbars',1024,768); return false;\">".CGI::escapeHTML($user_title)."</a></td><td class='OQ_ss_cmds'><button onclick=\"this.form.OQ_remove_saved_search_id.value = '$id'; this.form.submit();\" type='button'>delete</button></td></tr>";
  }
  $sth->finish();
  $buffer .= "</table><input type='hidden' name='OQ_remove_saved_search_id' />
<script>
if (! window.opwin) {
  window.opwin = function(lnk,target,opts) {
    window.open(lnk,target,opts);
  };
}
</script>" if $buffer;
  return $buffer;
}


1;
__END__

=pod

=head1 NAME

CGI::OptimalQuery - dynamic SQL query viewer

=head1 SYNOPSIS

  use CGI::OptimalQuery;

  # construct a CGI::OptimalQuery object
  my $oq = CGI::OptimalQuery->new({
    q => CGI->new(),
    dbh => $dbh,

    title => 'Employee List',

    select => {
      'NAME' => ['emp','emp.lname||', '||emp.fname", "Name"],
      'DEPT' => ["dept", "dept.name", "Department"]
    },

    # default shown columns alias list
    show => ['NAME', 'DEPT'],

    # defined joins included in the from clause
    joins => {
        'emp' => [ undef, 'employee', undef],
        'dept'=> ["employee", "
            left join ( SELECT name FROM dept ) dept
              on (emp.dept = dept.id)"]
    },
    options => {
      'CGI::OptimalQuery::InteractiveQuery' => {
        mutateRecord => sub { my $rec = shift; $$rec{NAME} = ''; }
        OQdataRCol => sub { my $rec = shift; return "stuff"; }
      }
    }
  );

  # output view to STDOUT
  $oq->output();


=head1 DESCRIPTION

Developer describes environment, output options, and database query; CGI::OptimalQuery provides user with a web interface to view, filter, sort, and export the data.

Sounds simple, but CGI::OptimalQuery does not write the SQL for the developer. It is only responsible for gluing the appropriate pieces of SQL together to form an optimized SQL query, and outputing the results in a format the user chooses.

This module has been tested for:

  1) SQLite
  2) MySQL
  3) PostgreSQL
  4) Microsoft SQL Server (must use MARS_Connection=yes in connection option)
  5) Oracle

The important elements the developer describes are what fields (select elements) the user can see and what data sets (join elements) those fields come from. Each select and join element can depend upon joins. For every Optimal Query there is one driving data set. The driving set does not depend on other data sets. For every row in the driving data set there can only be one corresponding row when joining the driving data set to other joins described in the joins configuration hash reference. This allows Optimal Query to optimize SQL and only include the appropriate joins when the user has selected a column from one of those joins. For example: If there are employee and department tables and the user only wants to see employee fields (not department fields) then Optimal Query will not join in the department table.

=head1 INSTALLATION

Configure your web server to allow it to serve the "Resources" directory containing static html/js/css files. This directory is located near the installation path. The easiest way to find it is to execute:

perl -MCGI::OptimalQuery -e '$_=$INC{"CGI/OptimalQuery.pm"};s/\.pm$/\/Resources\n/;print $_'

If you are using Apache, add the following config:

# required CGI::OptimalQuery static files
Alias /OptimalQuery/ /usr/local/share/perl5/CGI/OptimalQuery/Resources/

=head1 METHODS

=over 2

=item new ( \%CONFIG )

Returns an optimal query object. 

C<< \%CONFIG >> (a hash reference) describes the environment, query description, and output options using key and value pairs. Possible configuration elements are shown below. (required ones are first)

=item I<< REQUIRED CONFIGURATION >>

The following KEY/VALUES below for C<< %CONFIG >> in the call to C<new> are required.

=item B<< title => "This is the title of this Query" >>

=item B<< dbh => DBI->connect( .. ) >>

provides OptimalQuery a connection to the database.

=item B<< show => ['COLALIAS1', 'COLALIAS2'] >>

Default fields to show user when loading OptimalQuery the first time. This can also be set as a CGI param where the value is a comma separated list of column aliases. Example: "[NAME], [DOB]".

=item B<< select => { SELECT_ALIAS => [ DEP, SQL, NAME, OPTIONS ], .. } >>

The select configuration describes what fields from the query can be selected, filtered, and sorted. 

=over

=item B<< SELECT_ALIAS >> (STRING)

is the alias for the select field. This alias is used throughout the rest of the configuration to describe the field.

=item B<< DEP >> (STRING | ARRAYREF)

describes required joins that must be included to use the select specified. The DEP can be written as a string or an array reference of strings if multiple dependancies for the field exist.

=item B<< SQL >> (STRING | ARRAYREF)

SQL to display values for this field. Specified as a string or array reference where the first element is the SQL and each element after is a bind value.

=item B<< NAME >> (STRING | undef)

label describing the field name. If C<undef>, field cannot be selected by user and is considered hidden.

=item B<< OPTIONS >> (HASHREF | undef)

The following KEY/VALUES below describe OPTIONS used by the select configuration.

=over

=item B<< is_hidden => 1 >>

hides the select field and data from being viewed by the user. Data for this select is still available in callbacks and can be included in the hiddenFilter.

=item B<< always_select => 1 >>

tells OptimalQuery to always select the column regardless if it isn't explicitly being used in the show. This does not automatically make it shown to the user, but it will be available to the developer in callbacks.

=item B<< select_sql => (STRING | ARRAYREF) >>

=item B<< filter_sql => (STRING | ARRAYREF) >>

=item B<< sort_sql => (STRING | ARRAYREF) >>

SQL to use instead of the default SQL for the select for the context described.

=item B<< date_format => (STRING) >>

if column is a date and date format is specified, OptimalQuery will write SQL to use the date format appropriately.

Note: Oracle's date component also has a built-in time component. If the data is '11/24/2005 14:56:45' and the date_format is 'MM/DD/YYYY', the date will show up as '11/24/2005'. If a user tries to filter on date '11/24/2005' Oracle will only match '11/25/2005 00:00:00' leaving out results the user probably thinks should be included. In this case, the developer should trunc the date. Trunc strips the time component from a date field. Example:

  DATE_COL => ['DEP1', 'trunc(dep1.date_field)', 'My Date',
                 { date_format => 'MM/DD/YYYY' } ]

=back

=back

=item B<< joins => { JOIN_ALIAS => [ DEP, JOIN_SQL, WHERE_SQL, OPTIONS ], .. } >>

describes what tables to join in order to fulfill the dependancies used by the fields described in the SELECT HASHREF.

=over

=item B<< JOIN_ALIAS >> (STRING)

is the alias for the table or inline view decribed in the JOIN_SQL.

=item B<< DEP >> (STRING | ARRAYREF | undef)

describes required joins that this join depends upon. This should be C<undef> if and only if this is defining the driving data set.


=item B<< JOIN_SQL >> (STRING | ARRAYREF)

describes the SQL that is used in the join clause for the generated SQL. Example: "LEFT JOIN dept ON (emp.dep_id = dept.id)". If this describes the driving table, only the table name is needed. Inline views can also be used. Make sure you specify the alias on the view! Example: JOIN ( SELECT * FROM emp WHERE is_active = 'Y') active_emps

=item B<< WHERE_SQL >> (undef | STRING | ARRAYREF)

This is deprecated. It was used to describe the SQL in the where clause that was needed to join the table described in the from clause. Since SQL-92 allows developers to put the join SQL in the join, this should not be used.


=item B<< OPTIONS >> (undef | HASHREF)


The following KEY/VALUES below describe OPTIONS used by the joins configuration.

=over

=item B<< new_cursor => 1 >>

tells OptimalQuery to open a new cursor for this join. This can be used to select and filter multi-value fields.

=back

=back

=item I<< OPTIONAL CONFIGURATION >>

The following KEY/VALUES below for C<< %CONFIG >> in the call to C<new> are NOT required.


=item B<< AutoSetLongReadLen => 1 >>

Tells OptimalQuery to automatically set C<< $dbh->{SetLongReadLen} >>. Used only in Oracle. Enabling this setting may slow down OptimalQuery since it needs to do extra queries to set the length if LOBS exist. This is only enabled by default when using Oracle.


=item B<< check => 0 >>

Tells OptimalQuery to do additional checking to make sure the amount of rows in the driving table is equal even when including other joins. It is off by default because there can be a significant performace hit when enabled.

=item B<< debug => 0 >>

sends debug info to the error_handler (STDERR is default)

=item B<< error_handler => sub { ($err) = @_; } >>

intercept messages sent to the error handler. Very useful if you are running in a mod_perl env and want to redirect error messages using C<< $areq->log_error($msg) >>.


=item B<< filter => "[SELECT_COL_ALIAS] like 'foo' AND .." >>

=item B<< hiddenFilter => "[SELECT_COL_ALIAS] like 'foo' AND .." >>

default filters to include on a fresh loaded OptimalQuery. The value is translated to an SQL where clause using the grammar described in the I<FILTER GRAMMAR> section. Both filter options can also be set by CGI param.  Example: 
  <a href=/Search?filter=".escape_uri("[NAME] like 'foo'")

=item B<< module => { OverloadModuleLabel => PerlModuleName, .. } >>

This is an advanced feature that can help perl guru's change the factory blueprints for optimal query modules instantiated by CGI::OptimalQuery.

=item B<< named_filters => { NORMAL_NAMED_FILTER, CUSTOM_NAMED_FILTER, .. } >>

allow developers to create complex predefined sql for insertion in the where clause by the 'filter' and 'hiddenFilter' parameters. There are two types of named_filters: "normal" and "custom". Normal named filters are defined with static SQL. Custom named filters are dynamic and most often take arguments which influence the SQL and bind params generated via callbacks.

=over

=item B<< NORMAL_NAMED_FILTER >>

  filterNameAlias => [ DEP, SQL, NAME ]

DEP is a string or an ARRAY of strings describing the dependancies used by the named filter. SQL is a string or an arrayref with SQL/bind values that is used in the where clause when the named filter is enabled. The NAME is used to describe the named filter to the user running the report.

=item B<< CUSTOM_NAMED_FILTER >>

  filterNameAlias => {
    title => "text displayed on interactive filter",

    html_generator =>
      sub { my ($q, $prefix) = @_; return $html;},

    sql_generator  => sub {
      my %args = @_;
      return [$deps, $sql, $name];
    }
  }

The html_generator is used by InteractiveFilter to collect input from the user. The sql_generator converts the named filter & arguments into deps, sql, and a name. The deps can be returned as an array ref of string deps if more than one dep exists. The sql can also be returned as an array ref where the first element is the sql and the rest are bind values.

=back

=item B<< named_sorts => { SortName => [ DEP, SQL, NAME], .. } >>

Named sorts aren't really used that often. They are really implemented for completeness and work the same way as named_filters. 


=item B<< options => { MODULENAME => { OPT_KEY => OPT_VAL, .. } } >>

OptimalQuery is made up of several modules. The 'options' configuration allows developers to configure these modules. See section B<InteractiveQuery Options>.

  options => { 'CGI::InteractiveQuery' => \%opts }

=item B<< output_handler => sub { print @_; } >>

override default output handler (print to STDOUT), by defining this callback.

=item B<< q => new CGI() >>

Pass OptimalQuery thr CGI query object. OptimalQuery will automatically create a new CGI object if one is not passed in.

=item B<< queryDescr => "Some text describing the query" >> 

The query description is extra text describing the query and does not affect generated SQL. Can also be set as a CGI param.

=item B<< resourceURI => "/OptimalQuery" >> 

Path to optional OptimalQuery resources. Default path is shown.

=item B<< results_per_page_picker_nums => [10,20,50,100,'All'] >>

An interactive query displays a pager mechanism when the result set is larger than the rows_page param. This array reference allows a developer to override the default options a user can pick from the pager.

=item B<< rows_page => 10 >>

The default rows_page a user has when initially loading InteractiveQuery. Can also be set as a CGI param.

=item B<< savedSearchUserID => $user_id >>

InteractiveQuery can optionally save searches to a database so users can revisit them latter. To do this, saved searches are tied to a unique user id. See the "Saved Searches" section for more information on this topic.


=item B<< sort => "[COLALIAS1] DESC, [COLALIAS2]" >>

Default sort to show user when loading OptimalQuery for the first time. See the "SORT GRAMMAR" section for more information. Sort can also be specified as a CGI param.

=item B<< state_params => [ 'form_field1', .. ] >> 

If HTTP GET/POST params are required to dynamically generate a %CONFIG, the developer can specify the names of the GET/POST params in this array and OptimalQuery will automatically carry their state.

=item B<< URI => "/URI/Back/To/This/Page" >>

The URI back to the page the user is currently on. The default URI is taken from the REQUEST_URI ENV.


=item B<< URI_standalone => "/URI/Back/To/This/Page?layout=off" >>

By request, some developers use a separate URI to turn their layout system off so OptimalQuery can send the headers for content that can't be embedded.

=item output()

Output view to output_handler (STDOUT is default).

=back

=head1 INTERACTIVE QUERY OPTIONS

Options for an InteractiveQuery can be set by defining the following HASHREF in %CONFIG.

  $CONFIG{options}{'CGI::OptimalQuery::InteractiveQuery'} = 
    { KEY => VAL, .. };
                - OR - 
  $CONFIG{options}{'CGI::OptimalQuery::InteractiveQuery'}{KEY} = {VAL};

=over

=item B<< disable_select => 1 >>

=item B<< disable_filter => 1 >>

=item B<< disable_sort => 1 >>

Disables options for all fields. If you set all three your Optimal Query will work like a Pager.

=item B<< appendCSS => "OQdoc { color: blue; }" >>

=item B<< replaceCSS => "OQdoc { color: blue; }" >>

Allows developers to append or replace inline CSS. If you want to make your brain hurt, copy the CSS and manipulate rather than cook your own. For example:

  # replace odd row background color with blue
  my $css = $CGI::OptimalQuery::InteractiveQuery::get_defaultCSS();
  $css =~ s/ (tr\.OQdataRowTypeOdd\s*\{      (?# find selector)
              [^}]*?                         (?# match preceeding rules)
              background\-color\:            (?# match background rule)
             ).*?\;                          (?# match old color)
           /\1blue;/x;                       (?# replace with new color)
  $CONFIG{options}{'CGI::OptimalQuery::InteractiveQuery'}{replaceCSS} = $css;

The sane way of overriding the CSS is to create your own external file. To do this:

  # turns off default inline CSS
  $CONFIG{options}{'CGI::OptimalQuery::InteractiveQuery'}{replaceCSS} = '';

  # specify external CSS file
  $CONFIG{options}{'CGI::OptimalQuery::InteractiveQuery'}{htmlHeader} = 
    "<link href='/css/myOQ.css' rel='stylesheet' type='text/css'>";

Overriding CSS with an external file will disable setting the title bar color and resourceURI for icons. You must manually override them.

=item B<< buildEditLink => sub { } >>

  # override the built-in edit link builder
  buildEditLink => sub {
    my ($o,$rec,$opts) = @_;
    return "/link/record?id=$$rec{U_ID};act=edit"'
  }

=item B<< buildNewLink => sub { } >>

  # override the built-in edit link builder
  buildNewLink => sub {
    my ($o,$opts) = @_;
    return "/link/record?act=new"'
  }

=item B<< color => '#cccccc' >>

specify the background color of the optimal query GUI.

=item B<< editButtonLabel => 'edit' >>

=item B<< editLink => '/link/to/record' >>

OptimalQuery will automatically create an edit and new button if this is defined. When creating the link, OptimalQuery appends "?id=$$rec{U_ID};act=new;on_update=OQrefresh" or "?id=$$rec{U_ID};act=load;on_update=OQrefresh" to the link so the record module will know which view to load. "OQrefresh" is a function defined by Optimal Query that an external record module can call to update the Optimal Query window if a record has been updated.

=item B<< htmlFooter => "<h1>this is a footer</h1>" >>

=item B<< htmlHeader => "<h1>this is a header</h1>" >>

=item B<< httpHeader => CGI::header('text/html') >>

override httpHeader content. If you prefer to not have InteractiveQuery send the header, set this value to empty string.

=item B<< mutateRecord => sub { } >>

  mutateRecord => sub {
    my $rec = shift;

    # add html links to the person record 
    # if user selected the NAME field
    if (exists $$rec{NAME}) {
      $$rec{NAME} = "<A HREF=/PersonRecord?id=$$rec{ID}>".
        CGI::escapeHTML($$rec{NAME})."</A>";
    }
  }

=item B<< noEscapeCol => ['NAME'] >>

if certain columns should not be HTML escaped, let OptimalQuery know by adding them to this array.

=item B<< OQdataLCol => sub { } >>

=item B<< OQdataRCol => sub { } >>

Specify custom code to print the first or last column element. This is most often used to generate an view/edit button. If these callbacks are used, the editLink, and buildEditLink are ignored.

  OQdataLCol => sub {
    my ($rec) = @_; 
    return "<button onclick=\"OQopwin('/ViewRecord?id=$$rec{U_ID};on_update=OQrefresh';\">".
           "view</button>"; 
  }

=item B<< OQdocBottom => "bottom of the document (outside form)" >>

=item B<< OQdocTop => "top of the doc (outside form)" >>

=item B<< OQformBottom => "bottom of form" >>

=item B<< OQformTop => "top of form" >>

=item B<< WindowHeight => INT >>

=item B<< WindowWidth => INT >>

Specify popup window width, height.


=item B<< OQscript => " some javascript code (see examples below) " >>

OQscript gives you unlimited power to alter the output of optimal query by allowing you to enter javascript code that is executed client side
For example to add a new command button:

  OQscript => "
var e = document.getElementById('OQcmds');
e.innerHTML = '".CGI::OptimalQuery::escape_js(q|<button type=button onclick="window.alert('hello there');">hello</button>|)."' + e.innerHTML; 

=back


=head1 SAVED SEARCHES

InteractiveQuery can optionally save searches to a database so users can revisit them latter. To do this, saved searches are tied to a unique user id. Developers should tell OptimalQuery the user id by defining 'savedSearchUserID' in their %CONFIG.

 $config{savedSearchUserID} = $user_id;

Saved Searches are stored in a table in the database pointed to by the database handle defined in $config{dbh}. The following table must exist before using saved searches.

  -- For mysql:
  CREATE TABLE oq_saved_search (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id INT UNSIGNED,
      FOREIGN KEY fk_oqsavedsearch_userid (user_id)
        REFERENCES XYZ(id) ON DELETE CASCADE,
    uri VARCHAR(100) NOT NULL,
    oq_title VARCHAR(1000) NOT NULL,
    user_title VARCHAR(1000) NOT NULL,
    params TEXT,
    CONSTRAINT unq_oq_saved_search UNIQUE (user_id,uri,oq_title,user_title)
  );

  -- For Oracle:
  CREATE TABLE oq_saved_search (
    id NUMBER PRIMARY KEY,
    user_id NUMBER NOT NULL REFERENCES XYZ(id) ON DELETE CASCADE,
    uri VARCHAR2(100) NOT NULL,
    oq_title VARCHAR2(1000) NOT NULL,
    user_title VARCHAR2(1000) NOT NULL,
    params CLOB,
    CONSTRAINT unq_oq_saved_search UNIQUE (user_id,uri,oq_title,user_title)
  );
  CREATE SEQUENCE s_oq_saved_search;

Replace XYZ(id) with the name of the user table and primary key id.

Optimal Query also provides a canned "Show My Saved Searches" HTML form component that can be embedded inside an HTML form. It can be used in the following manner:

  use use CGI::OptimalQuery();

  my $saved_searches_html = CGI::OptimalQuery::get_saved_search_list(
    $cgi_query, $dbh, $userid);
  print $saved_searches_html;

Use CSS to stylize the output.


=head1 FILTER GRAMMAR

  start: exp /^$/

  exp:
     '(' exp ')' logicOp exp
   | '(' exp ')'
   | comparisonExp logicOp exp
   | comparisonExp

  comparisonExp:
     namedFilter
   | colAlias compOp colAlias
   | colAlias compOp bindVal

  bindVal: float | quotedString

  logicOp:
     /and/i
   | /or/i

  namedFilter: /\w+/ '(' namedFilterArg(s? /,/) ')'

  namedFilterArg: quotedString | float | unquotedIdentifier

  unquotedIdentifier: /\w+/

  colAlias: '[' /\w+/ ']'

  float:
     /\-?\d*\.?\d+/
   | /\-?\d+\.?\d*/

  quotedString:
     /'.*?(?<!\\)'/
   | /".*?(?<!\\)"/

  compOp:
     '<=' | '>=' | '=' | '!=' | '<' | '>' |
     /contains/i | /not\ contains/i | /like/i | /not\ like/i

=head1 SORT GRAMMAR

  start: expList /^$/

  expList: expression(s? /,/)

  expression:
     namedSort opt(?)
   | colAlias  opt(?)

  opt: /desc/i

  namedSort: /\w+/ '(' namedSortArg(s? /,/) ')'
  namedSortArg: quotedString | float

  colAlias: '[' /\w+/ ']'

  float:
     /\-?\d*\.?\d+/
   | /\-?\d+\.?\d*/

  quotedString:
     /'.*?(?<!\\)'/
   | /".*?(?<!\\)"/

=head1 AUTHOR

    Philip Collins
    CPAN ID: LIKEHIKE
    University of New Hampshire
    Philip.Collins@unh.edu
    https://github.com/collinsp

=head1 CONTRIBUTE

    https://github.com/collinsp/perl-CGI-OptimalQuery

=head1 COPYRIGHT

This program is free software licensed under the...

	The MIT License

The full text of the license can be found in the
LICENSE file included with this module.

=cut
