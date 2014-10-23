#!/usr/bin/perl

use strict;
use FindBin qw($Bin);
use lib "$Bin/../../lib"; # include project lib

use DBI();
use CGI::OptimalQuery();
use CGI::OptimalQuery::EmailMergeTool();

chdir "$Bin/..";

my $dbh = DBI->connect("dbi:SQLite:dbname=db/dat.db","","");

my %schema = (
  'dbh' => $dbh,
  'title' => 'The People',
  'select' => {
    'U_ID' => ['person', 'person.id', 'SYS ID', { always_select => 1 }],
    'NAME' => ['person', 'person.name', 'Name'],
    'EMAIL' => ['person', 'person.email', 'Email']
  },
  'joins' => {
    'person' => [undef, 'person']
  },

  'tools' => {
    'emailmerge' => {
      'title' => 'Email Merge',
      'handler' => \&CGI::OptimalQuery::EmailMergeTool::handler,
      'options' => {
        readonly_to => 0,
        from => 'pmc2@sr.unh.edu',
        readonly_from => 1,
        template_vars => {
          'CURRENT_USER_EMAIL' => 'test.me@foo.com',
        }
      }
    }
  }
);

CGI::OptimalQuery->new(\%schema)->output();
