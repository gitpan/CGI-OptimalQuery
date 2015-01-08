#!/usr/bin/perl

use strict;
use FindBin qw($Bin);
use lib "$Bin/../../lib"; # include project lib

use DBI();
use CGI::OptimalQuery();

chdir "$Bin/..";

my $dbh = DBI->connect("dbi:SQLite:dbname=db/dat.db","","");

my %schema = (
  'dbh' => $dbh,
  'module' => 'InteractiveQuery',
  'savedSearchUserID' => 12345,
  'title' => 'The Inventory',
  'select' => {
    'U_ID' => ['inventory', 'inventory.id', 'SYS ID', { always_select => 1 }],
    'BARCODE' => ['inventory', 'inventory.barcode', 'Barcode'],
    'DATE_ACQUIRED' => ['inventory', 'inventory.date_acquired', 'Date Acquired'],
    'DATE_DISPOSED' => ['inventory', 'inventory.date_disposed', 'Date Disposed'],
    'PRODUCT_NAME' => ['product', 'product.name', 'Product Name'],
    'PRODNO' => ['product', 'product.prodno', 'Product No.'],
    'MANUFACT' => ['manufact', 'manufact.name', 'Manufacturer'],
    'OWNER' => ['owner', 'owner.name', 'Owner Name'],
    'OWNER_EMAIL' => ['owner', 'owner.email', 'Owner Email']
  },
  'show' => "BARCODE,PRODUCT_NAME,MANUFACT",
  'filter' => "[DATE_DISPOSED]=''",
  'joins' => {
    'inventory' => [undef, 'inventory'],
    'product' => ['inventory', 'LEFT JOIN product ON (inventory.product=product.id)'],
    'manufact' => ['product', 'LEFT JOIN manufact ON (product.manufact=manufact.id)'],
    'owner' => ['inventory', 'LEFT JOIN person owner ON (inventory.owner=owner.id)']
  },
  'options' => {
    'CGI::OptimalQuery::InteractiveQuery' => {
      'editLink' => 'record.pl'
    }
  }
);

CGI::OptimalQuery->new(\%schema)->output();
