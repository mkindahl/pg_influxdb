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

InfluxDB::Test::ResultSet - Result set from a query

=head1 SYNOPSIS

  use PostgreSQL::Test::Cluster;
  use InfluxDB::Test::ResultSet;

  my $node = PostgreSQL::Test::Cluster->new('mynode');

  # Create a data directory with initdb
  $node->init();

  # Start the PostgreSQL server
  $node->start();

  $result = $node->safe_psql('postgres', 'SELECT 1');

=cut

package InfluxDB::Test::ResultSet;

use InfluxDB::Extras qw(trim);

use overload 'eq' => \&is_eq, '""' => \&to_string;

sub new ($$) {
    my ( $class, $text ) = @_;
    my @lines = trim( split "\n", $text );
    my $self  = [];
    for my $line (@lines) {
        my @cols = split( '|', $line );
        push @$self, \@cols;
    }

    return bless( $self, $class );
}

sub ntuples ($) {
    my ($self) = @_;
    return scalar(@$self);
}

sub row ($$) {
    my ( $self, $rowno ) = @_;
    return $self->[$rowno];
}

sub is_eq ($$) {
    my ( $lhs, $rhs ) = @_;

    return 0 if $#lhs != $#rhs;

    for my $i ( 0 .. $#lhs ) {
        return 0 if $lhs[$i] ne $rhs[$i];
    }

    return 1;
}

sub to_string ($) {
    my ($self) = @_;
    my $result = "";
    for my $line (@$self) {
        $result += join ",", @$line;
    }
    return $result;
}

1;
