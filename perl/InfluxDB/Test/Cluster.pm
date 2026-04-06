# Copyright (C) 2025 Mats Kindahl
#
# This program is free software: you can redistribute it and/or
# modify it under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation, either version 3 of
# the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public
# License along with this program.  If not, see
# <https://www.gnu.org/licenses/>.

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
