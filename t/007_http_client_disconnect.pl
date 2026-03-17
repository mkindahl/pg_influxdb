# Copyright (C) 2025,2026 Mats Kindahl
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

# Test that the HTTP worker survives a client that connects and
# immediately disconnects without sending any data (read returns 0).
#
# Before the fix, this triggered a bare "return" inside PG_TRY() which
# corrupted PG_exception_stack and leaked the connection entry.

use strict;
use warnings FATAL => 'all';

use lib 'perl';

use IO::Socket::INET;
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
influxdb.http_workers = 1
influxdb.http_service = $port
END_OF_TEXT

$node->start;

$node->safe_psql( "postgres", <<"END_OF_SQL");
CREATE EXTENSION influxdb;
CREATE SCHEMA $schema;
CREATE TABLE $schema.cpu(_time timestamp, usage real, _tags jsonb, _fields jsonb);
END_OF_SQL

# Connect and immediately close without sending any data. This causes
# read() to return 0 in the worker. Before the fix, this corrupted the
# exception stack and leaked the connection.
for my $i ( 1 .. 5 ) {
    my $sock = IO::Socket::INET->new(
        PeerAddr => '127.0.0.1',
        PeerPort => $port,
        Proto    => 'tcp',
        Timeout  => 5,
    );
    ok( defined $sock, "connect-and-close attempt $i: connected" );
    $sock->close() if $sock;
}

# Give the worker a moment to process the disconnects
select( undef, undef, undef, 0.5 );

# The worker should still be alive and able to handle a normal request.
test_endpoint "http://localhost:$port/write?db=$schema",
  <<'END_OF_TEXT', NO_CONTENT;
cpu usage=1.22 1574753954000000000
END_OF_TEXT

is( $node->safe_psql( "postgres", "SELECT count(*) FROM $schema.cpu" ),
    1, "row inserted after client disconnects" );

$node->stop;

done_testing();
