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
use IO::Socket::INET;
use Time::HiRes qw(usleep);

my $node      = InfluxDB::Test::Cluster->new('main');
my $http_port = PostgreSQL::Test::Cluster::get_free_port();
my $udp_port  = PostgreSQL::Test::Cluster::get_free_port();
my $schema    = "metrics";

$node->init;
$node->append_conf( 'postgresql.conf', <<"END_OF_TEXT");
shared_preload_libraries = 'influxdb'
influxdb.database = 'postgres'
influxdb.http_workers = 1
influxdb.http_service = $http_port
influxdb.udp_service = $udp_port
influxdb.udp_workers = 1
influxdb.udp_schema = $schema
influxdb.udp_workers = 1
END_OF_TEXT

$node->start;

$node->safe_psql( "postgres", <<"END_OF_TEXT");
CREATE EXTENSION influxdb;
CREATE SCHEMA $schema;
CREATE TABLE $schema.cpu(_time timestamp, _tags jsonb, _fields jsonb);
CREATE TABLE $schema.disk(_time timestamp, mode text, free integer, _tags jsonb, _fields jsonb);
END_OF_TEXT

# Helper to send UDP data
sub send_udp {
    my ( $port, $data ) = @_;
    my $sock = IO::Socket::INET->new(
        PeerAddr => '127.0.0.1',
        PeerPort => $port,
        Proto    => 'udp',
    ) or die "Cannot create UDP socket: $!\n";
    $sock->send($data);
    $sock->close();
}

# Test: single line protocol point via UDP
send_udp( $udp_port, "cpu,host=server01 value=0.64 1574753954000000000\n" );

# Give the worker time to process
usleep(500_000);

my $result = $node->safe_psql( "postgres", "SELECT count(*) FROM $schema.cpu" );
is( $result, '1', 'single data point inserted via UDP' );

$result = $node->safe_psql( "postgres",
    "SELECT _time, _tags->>'host', _fields->>'value' FROM $schema.cpu ORDER BY _time" );
my $expected = InfluxDB::Test::ResultSet->new('2019-11-26 07:39:14|server01|0.64');
is( $result, $expected, 'single data point has correct values' );

# Test: multiple lines in a single datagram
send_udp( $udp_port, <<"END_OF_TEXT");
disk,mode=rw,path=/data free=100i,total=1000i,used_percent=10.0 1574753954000000000
disk,mode=ro,path=/boot free=200i,total=500i,used_percent=60.0 1574753964000000000
disk,mode=rw,path=/home free=300i,total=2000i,used_percent=15.0 1574753974000000000
END_OF_TEXT

usleep(500_000);

$result = $node->safe_psql( "postgres", "SELECT count(*) FROM $schema.disk" );
is( $result, '3', 'multiple data points inserted via single UDP datagram' );

$result =
    $node->safe_psql( "postgres", "SELECT _time, mode, free FROM $schema.disk ORDER BY _time" );
$expected = InfluxDB::Test::ResultSet->new(<<'END_OF_TEXT');
2019-11-26 07:39:14|rw|100
2019-11-26 07:39:24|ro|200
2019-11-26 07:39:34|rw|300
END_OF_TEXT

is( $result, $expected, 'multiple data points have correct values' );

# Test: malformed data does not crash the worker (errors are logged, not sent)
send_udp( $udp_port, "this is not valid line protocol\n" );

usleep(500_000);

# Worker should still be alive - send another valid point
send_udp( $udp_port, "cpu,host=server02 value=1.23 1574754000000000000\n" );

usleep(500_000);

$result = $node->safe_psql( "postgres", "SELECT count(*) FROM $schema.cpu" );
is( $result, '2', 'worker survives malformed data and processes subsequent data' );

$node->stop;

done_testing();
