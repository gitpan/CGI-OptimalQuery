#!/usr/bin/perl

use strict;
use FindBin qw($Bin);
use lib "$Bin/../../lib"; # include project lib

use DBI();
use CGI();
use CGI::OptimalQuery();

chdir "$Bin/..";

my $dbh = DBI->connect("dbi:SQLite:dbname=db/dat.db","","");
my $q = new CGI();
my $userid = 12345;

my $saved_searches_html = CGI::OptimalQuery::get_saved_search_list($q, $dbh, $userid);

print CGI::header(), 
"<!DOCTYPE html>
<html>
<body>
<form method=post>
<h1>My Simple Dashboard <button type=submit>reload</button></h1>
<ul>
  <li><a href=inventory.pl target=_blank>inventory</a>
  <li><a href=people.pl target=_blank>people</a>
  <li><a href=product.pl target=_blank>product</a>
  <li><a href=manufact.pl target=_blank>manufacturers</a>
  <li><a href=emailmerge_example.pl target=_blank>email merge example</a>
  <li><a href=autoactions_example.pl target=_blank>auto actions</a>
  <li><a href=on_select.pl target=_blank>on_select demo</a>
  <li><a href=on_selectmultiple.pl target=_blank>on_selectmultiple demo</a>
  <li><a href=named_filters.pl target=_blank>named_filters demo</a>
  <li><a href=old.pl target=_blank>old v1 example</a>
</ul>

<h2>Saved Searches</h2>
$saved_searches_html
</form>

</body>
</html>";
