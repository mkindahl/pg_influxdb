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

use strict;
use warnings FATAL => 'all';

use lib 'perl';

use InfluxDB::Test::Cluster;
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;
use IO::Socket::INET;
use Time::HiRes qw(usleep);

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

my $schema = "metrics";

###
### Test: negative value is out of range (server starts with warning)
###
{
    my $node      = InfluxDB::Test::Cluster->new('neg');
    my $http_port = PostgreSQL::Test::Cluster::get_free_port();
    my $udp_port  = PostgreSQL::Test::Cluster::get_free_port();

    $node->init;
    $node->append_conf( 'postgresql.conf', <<"END_OF_TEXT");
shared_preload_libraries = 'influxdb'
influxdb.database = 'postgres'
influxdb.http_workers = 1
influxdb.http_service = $http_port
influxdb.udp_service = $udp_port
influxdb.udp_workers = 1
influxdb.udp_schema = $schema
influxdb.udp_read_buffer = -1
END_OF_TEXT

    $node->start;

    my $log         = $node->logfile;
    my $logcontents = slurp_file($log);
    like(
        $logcontents,
        qr/outside the valid range for parameter "influxdb.udp_read_buffer"/,
        'negative udp_read_buffer generates out-of-range warning'
    );

    $node->stop;
}

###
### Test: value exceeding max is out of range (server starts with warning)
###
{
    my $node      = InfluxDB::Test::Cluster->new('max');
    my $http_port = PostgreSQL::Test::Cluster::get_free_port();
    my $udp_port  = PostgreSQL::Test::Cluster::get_free_port();

    $node->init;
    $node->append_conf( 'postgresql.conf', <<"END_OF_TEXT");
shared_preload_libraries = 'influxdb'
influxdb.database = 'postgres'
influxdb.http_workers = 1
influxdb.http_service = $http_port
influxdb.udp_service = $udp_port
influxdb.udp_workers = 1
influxdb.udp_schema = $schema
influxdb.udp_read_buffer = 128MB
END_OF_TEXT

    $node->start;

    my $log         = $node->logfile;
    my $logcontents = slurp_file($log);
    like(
        $logcontents,
        qr/outside the valid range for parameter "influxdb.udp_read_buffer"/,
        'udp_read_buffer exceeding max generates out-of-range warning'
    );

    $node->stop;
}

###
### Test: very small buffer size still works
###
{
    my $node      = InfluxDB::Test::Cluster->new('small');
    my $http_port = PostgreSQL::Test::Cluster::get_free_port();
    my $udp_port  = PostgreSQL::Test::Cluster::get_free_port();

    $node->init;
    $node->append_conf( 'postgresql.conf', <<"END_OF_TEXT");
shared_preload_libraries = 'influxdb'
influxdb.database = 'postgres'
influxdb.http_workers = 1
influxdb.http_service = $http_port
influxdb.udp_service = $udp_port
influxdb.udp_workers = 1
influxdb.udp_schema = $schema
influxdb.udp_read_buffer = 1kB
END_OF_TEXT

    $node->start;

    $node->safe_psql( "postgres", <<"END_OF_TEXT");
CREATE EXTENSION influxdb;
CREATE SCHEMA $schema;
CREATE TABLE $schema.cpu(_time timestamp, _tags jsonb, _fields jsonb);
END_OF_TEXT

    send_udp( $udp_port, "cpu,host=server01 value=0.64 1574753954000000000\n" );

    usleep(500_000);

    my $result = $node->safe_psql( "postgres", "SELECT count(*) FROM $schema.cpu" );
    is( $result, '1', 'data point inserted with very small udp_read_buffer (1kB)' );

    $node->stop;
}

###
### Test: explicit zero (OS default) works
###
{
    my $node      = InfluxDB::Test::Cluster->new('zero');
    my $http_port = PostgreSQL::Test::Cluster::get_free_port();
    my $udp_port  = PostgreSQL::Test::Cluster::get_free_port();

    $node->init;
    $node->append_conf( 'postgresql.conf', <<"END_OF_TEXT");
shared_preload_libraries = 'influxdb'
influxdb.database = 'postgres'
influxdb.http_workers = 1
influxdb.http_service = $http_port
influxdb.udp_service = $udp_port
influxdb.udp_workers = 1
influxdb.udp_schema = $schema
influxdb.udp_read_buffer = 0
END_OF_TEXT

    $node->start;

    $node->safe_psql( "postgres", <<"END_OF_TEXT");
CREATE EXTENSION influxdb;
CREATE SCHEMA $schema;
CREATE TABLE $schema.cpu(_time timestamp, _tags jsonb, _fields jsonb);
END_OF_TEXT

    send_udp( $udp_port, "cpu,host=server01 value=0.64 1574753954000000000\n" );

    usleep(500_000);

    my $result = $node->safe_psql( "postgres", "SELECT count(*) FROM $schema.cpu" );
    is( $result, '1', 'data point inserted with udp_read_buffer = 0 (OS default)' );

    $node->stop;
}

done_testing();
