
=pod

=head1 NAME

InfluxDB::Test::Cluster - Cluster implementation with some extras

=head1 SYNOPSIS

  use InfluxDB::Test::Cluster;

  my $node = InfluxDB::Test::Cluster->new('mynode');

  # Create a data directory with initdb
  $node->init();

  # Start the PostgreSQL server
  $node->start();

  $result = $node->safe_psql('postgres', 'SELECT 1');

  $result->rows();

=cut

package InfluxDB::Test::Cluster;

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use InfluxDB::Test::ResultSet;

use parent 'PostgreSQL::Test::Cluster';

sub safe_psql {
    my $self = shift;
    my $text = $self->SUPER::safe_psql(@_);
    return InfluxDB::Test::ResultSet->new($text);
}

1;
