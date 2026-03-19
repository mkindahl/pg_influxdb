# InfluxDB API to PostgreSQL. Copyright (C) 2025 Mats Kindahl
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

use strict;
use warnings FATAL => 'all';

use lib 'perl';

use InfluxDB::Test::Cluster;
use PostgreSQL::Test::Cluster;
use Test::More;
use InfluxDB::Extras ':all';

my $node   = InfluxDB::Test::Cluster->new('main');
my $port   = PostgreSQL::Test::Cluster::get_free_port();
my $schema = "metrics";

$node->init;
$node->append_conf( 'postgresql.conf', <<"END_OF_TEXT");
shared_preload_libraries = 'influxdb'
influxdb.database = 'postgres'
influxdb.http_workers = 2
influxdb.http_service = $port
END_OF_TEXT

$node->start;

$node->safe_psql( "postgres", <<"END_OF_TEXT");
CREATE EXTENSION influxdb;
CREATE SCHEMA $schema;
CREATE TABLE $schema.disk(_time timestamp, mode text, free integer, _tags jsonb, _fields jsonb);
END_OF_TEXT

# Generate 1000 lines of line protocol data (~80KB, well above the 8KB
# read buffer to guarantee multiple chunked reads).
my @lines;
for my $cnt ( 0 .. 999 ) {
    my $free      = 1234 * $cnt;
    my $total     = 1024 * 1024 - $free;
    my $timestamp = 1574853954000000000 + 1000000000 * $cnt;
    push @lines,
        "disk,mode=rw,path=/boot/efi free=${free}i,total=${total}i,used_percent=1.49 $timestamp";
}

# Test 1: Large body with trailing newline
my $content_with_newline = join( "\n", @lines ) . "\n";

cmp_ok( length($content_with_newline),
    ">", 64 * 1024, "payload with trailing newline is larger than 64 KiB" );

test_endpoint "http://localhost:$port/write?db=$schema", $content_with_newline, NO_CONTENT;

is( $node->safe_psql( "postgres", "SELECT count(*) FROM $schema.disk" ),
    1000, "large body with trailing newline inserts all 1000 rows" );

# Clear table for next test
$node->safe_psql( "postgres", "TRUNCATE $schema.disk" );

# Test 2: Large body without trailing newline (exercises
# on_message_complete remainder flush)
my $content_no_newline = join( "\n", @lines );

cmp_ok( length($content_no_newline),
    ">", 64 * 1024, "payload without trailing newline is larger than 64 KiB" );

test_endpoint "http://localhost:$port/write?db=$schema", $content_no_newline, NO_CONTENT;

is( $node->safe_psql( "postgres", "SELECT count(*) FROM $schema.disk" ),
    1000, "large body without trailing newline inserts all 1000 rows" );

$node->stop;

done_testing();
