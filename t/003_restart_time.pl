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

my $worker_query = <<"END_OF_QUERY";
SELECT datid, datname, pid, backend_type, application_name, state, query
  FROM pg_stat_activity
 WHERE datname = current_database()
   AND pid != pg_backend_pid()
   AND backend_type LIKE '%InfluxDB%';
END_OF_QUERY

sub check_influxdb_workers {
    my ( $node, $dbname ) = @_;
    return $node->safe_psql( $dbname, $worker_query );
}

my ( $output, $response, $json, $expected, $result );

my $node   = PostgreSQL::Test::Cluster->new('main');
my $port   = PostgreSQL::Test::Cluster::get_free_port();
my $dbname = 'postgres';
my $schema = "metrics";

$node->init;

# Create a configuration with a restart time of 10 seconds
$node->append_conf( 'postgresql.conf', <<"END_OF_TEXT");
shared_preload_libraries = 'influxdb'
influxdb.database = '$dbname'
influxdb.http_workers = 1
influxdb.http_service = $port
influxdb.http_worker_restart_time = 5
END_OF_TEXT

$node->start;

# Create extension and schema
$node->safe_psql( "postgres", <<"END_OF_SQL");
CREATE EXTENSION influxdb;
CREATE SCHEMA $schema;
END_OF_SQL

# Create table with a trigger that generates a fatal error to be able
# to test the worker restart. We cannot use PL/pgSQL since it does not
# allow raising fatal errors, but we can use a C language function.
$node->safe_psql( "postgres", <<"END_OF_SQL");
CREATE TABLE $schema.cpu(_time timestamp, _tags jsonb, _fields jsonb);

CREATE TRIGGER fatal_trigger
    BEFORE INSERT OR UPDATE OR DELETE ON $schema.cpu
    FOR EACH ROW
    EXECUTE FUNCTION influxdb.trigger_fatal_error();
END_OF_SQL

# Check that we have a worker before in the correct state.
print STDERR check_influxdb_workers($node, "postgres"), "\n";

# Trying to insert metrics on cpu table should generate a fatal
# error. This will close the connection, hence result in an "undef"
# response.
$output = curl "http://localhost:$port/write?db=$schema", <<'END';
cpu usage=1.22 1574753954000000000
END

is($output, '', "empty string as expected");

# Check that we do not have a worker
print STDERR check_influxdb_workers($node, "postgres"), "\n";

# Sleep until worker restarts
sleep(10);

# Check that we have a worker.
print STDERR check_influxdb_workers($node, "postgres"), "\n";

$node->stop;

done_testing();
