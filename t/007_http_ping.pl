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
use HTTP::Response;
use IPC::Run;

my $node = InfluxDB::Test::Cluster->new('main');
my $port = PostgreSQL::Test::Cluster::get_free_port();

$node->init;
$node->append_conf( 'postgresql.conf', <<"END_OF_TEXT");
shared_preload_libraries = 'influxdb'
influxdb.database = 'postgres'
influxdb.http_workers = 2
influxdb.http_service = $port
END_OF_TEXT

$node->start;

$node->safe_psql( "postgres", "CREATE EXTENSION influxdb" );

# Test GET /ping returns 204 with X-Influxdb-Version header
{
    my ( $stdin, $stdout, $stderr );
    IPC::Run::run [ "curl", "-is", "http://localhost:$port/ping" ],
      \$stdin, \$stdout, \$stderr;
    my $response = HTTP::Response->parse($stdout);

    is( $response->code, 204, "GET /ping returns 204" );
    is( $response->header('X-Influxdb-Version'),
        'pg_influxdb', "/ping returns X-Influxdb-Version header" );
}

# Test HEAD /ping also returns 204
{
    my ( $stdin, $stdout, $stderr );
    IPC::Run::run [ "curl", "-is", "--head", "http://localhost:$port/ping" ],
      \$stdin, \$stdout, \$stderr;
    my $response = HTTP::Response->parse($stdout);

    is( $response->code, 204, "HEAD /ping returns 204" );
    is( $response->header('X-Influxdb-Version'),
        'pg_influxdb', "HEAD /ping returns X-Influxdb-Version header" );
}

$node->stop;

done_testing();
