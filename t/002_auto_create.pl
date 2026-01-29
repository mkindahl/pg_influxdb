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

use PostgreSQL::Test::Cluster;
use Test::More;
use InfluxDB::Extras ':all';

my ( $output, $response, $json, $expected, $result );

my $node = PostgreSQL::Test::Cluster->new('main');
my $port = PostgreSQL::Test::Cluster::get_free_port();

print "Using port $port for the service\n";

$node->init;
$node->append_conf( 'postgresql.conf', <<"END_OF_TEXT");
shared_preload_libraries = 'influxdb'
influxdb.database = 'postgres'
influxdb.http_workers = 2
influxdb.http_service = $port
influxdb.auto_create_table = on
END_OF_TEXT

$node->start;

my $schema = "metrics";

$node->safe_psql( "postgres", <<"END_OF_TEXT");
CREATE EXTENSION influxdb;
CREATE SCHEMA $schema;
END_OF_TEXT

# Check that inserting into a measurement table that does not exist
# will create it.
$output = curl "http://localhost:$port/write?db=$schema", <<'END_OF_LINES';
cpu usage=1.2 1574753954000000000
cpu,kind=i836 usage=1.6 1574763954000000000
END_OF_LINES

$response = HTTP::Response->parse($output);
is_response( $response, 204, 'No Content' );
has_headers( $response, 'Date', 'Connection' );

$result = $node->safe_psql( "postgres", <<"END_OF_SQL" );
select *
  from $schema.cpu
order by _time;
END_OF_SQL

$expected = trim(<<'END_OF_TEXT');
2019-11-26 07:39:14|{}|{"usage": 1.2}
2019-11-26 10:25:54|{"kind": "i836"}|{"usage": 1.6}
END_OF_TEXT

is( $result, $expected );

$node->stop;

done_testing();
