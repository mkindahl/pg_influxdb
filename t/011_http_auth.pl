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
use Test::More;
use InfluxDB::Extras ':all';
use HTTP::Response;
use IPC::Run;

my ( $result, $expected );

my $schema   = "metrics";
my $username = "influx_user";
my $password = "influx_pass";

# First test: with auth enabled, credentials are verified against pg_authid
{
    my $node = InfluxDB::Test::Cluster->new('auth_on');
    my $port = PostgreSQL::Test::Cluster::get_free_port();

    $node->init;
    $node->append_conf( 'postgresql.conf', <<"END_OF_TEXT");
shared_preload_libraries = 'influxdb'
influxdb.database = 'postgres'
influxdb.http_workers = 2
influxdb.http_service = $port
influxdb.http_auth = on
END_OF_TEXT

    $node->start;

    # Create a PostgreSQL role with a password for auth testing
    $node->safe_psql( "postgres", <<"END_OF_TEXT");
CREATE USER $username WITH PASSWORD '$password';
CREATE EXTENSION influxdb;
CREATE SCHEMA $schema;
CREATE TABLE $schema.cpu(_time timestamp, host text, usage_idle float8, _tags jsonb, _fields jsonb);
END_OF_TEXT

    # Test: no credentials -> 401
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [
            "curl",
            "-is",
            "--header",
            "Content-Type: text/plain",
            "--header",
            "Connection: close",
            "--data-binary",
            "cpu,host=h1 usage_idle=99.5 1574753954000000000",
            "http://localhost:$port/write?db=$schema"
            ],
            \$stdin, \$stdout, \$stderr;

        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 401, "no credentials returns 401" );
        like( $response->header('WWW-Authenticate'),
            qr/Basic/, "401 includes WWW-Authenticate header" );
    }

    # Test: wrong credentials -> 401
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [
            "curl",
            "-is",
            "-u",
            "wrong:creds",
            "--header",
            "Content-Type: text/plain",
            "--header",
            "Connection: close",
            "--data-binary",
            "cpu,host=h1 usage_idle=99.5 1574753954000000000",
            "http://localhost:$port/write?db=$schema"
            ],
            \$stdin, \$stdout, \$stderr;

        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 401, "wrong credentials returns 401" );
    }

    # Test: valid credentials via Basic Auth header -> 204
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [
            "curl",
            "-is",
            "-u",
            "$username:$password",
            "--header",
            "Content-Type: text/plain",
            "--header",
            "Connection: close",
            "--data-binary",
            "cpu,host=authhost usage_idle=99.5 1574753954000000000",
            "http://localhost:$port/write?db=$schema"
            ],
            \$stdin, \$stdout, \$stderr;

        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 204, "valid Basic Auth credentials returns 204" );
    }

    $result = $node->safe_psql( "postgres", <<"END_OF_SQL" );
select _time, host, usage_idle
  from $schema.cpu
 where host = 'authhost'
END_OF_SQL

    $expected = InfluxDB::Test::ResultSet->new(<<'END_OF_TEXT');
2019-11-26 07:39:14|authhost|99.5
END_OF_TEXT

    is( $result, $expected, "data was inserted with valid auth" );

    # Test: valid credentials via query parameters -> 204
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [
            "curl",
            "-is",
            "--header",
            "Content-Type: text/plain",
            "--header",
            "Connection: close",
            "--data-binary",
            "cpu,host=queryauth usage_idle=88.8 1574753964000000000",
            "http://localhost:$port/write?db=$schema&u=$username&p=$password"
            ],
            \$stdin, \$stdout, \$stderr;

        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 204, "valid query param credentials returns 204" );
    }

    $result = $node->safe_psql( "postgres", <<"END_OF_SQL" );
select _time, host, usage_idle
  from $schema.cpu
 where host = 'queryauth'
END_OF_SQL

    $expected = InfluxDB::Test::ResultSet->new(<<'END_OF_TEXT');
2019-11-26 07:39:24|queryauth|88.8
END_OF_TEXT

    is( $result, $expected, "data was inserted with query param auth" );

    # Test: /ping does not require auth
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [ "curl", "-is", "http://localhost:$port/ping" ], \$stdin, \$stdout, \$stderr;
        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 204, "/ping does not require auth" );
    }

    # Test: valid role but wrong password -> 401
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [
            "curl",
            "-is",
            "-u",
            "$username:wrongpassword",
            "--header",
            "Content-Type: text/plain",
            "--header",
            "Connection: close",
            "--data-binary",
            "cpu,host=h1 usage_idle=99.5 1574753954000000000",
            "http://localhost:$port/write?db=$schema"
            ],
            \$stdin, \$stdout, \$stderr;

        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 401, "valid role with wrong password returns 401" );
    }

    # Test: role without a password -> 401
    {
        $node->safe_psql( "postgres", "CREATE USER no_pass_user" );

        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [
            "curl",
            "-is",
            "-u",
            "no_pass_user:anything",
            "--header",
            "Content-Type: text/plain",
            "--header",
            "Connection: close",
            "--data-binary",
            "cpu,host=h1 usage_idle=99.5 1574753954000000000",
            "http://localhost:$port/write?db=$schema"
            ],
            \$stdin, \$stdout, \$stderr;

        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 401, "role without password returns 401" );
    }

    $node->stop;
}

# Second test: auth disabled -> everything works without credentials
{
    my $node = InfluxDB::Test::Cluster->new('auth_off');
    my $port = PostgreSQL::Test::Cluster::get_free_port();

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
CREATE TABLE $schema.cpu(_time timestamp, host text, usage_idle float8, _tags jsonb, _fields jsonb);
END_OF_TEXT

    # Test: no auth configured, no credentials -> 204
    test_endpoint "http://localhost:$port/write?db=$schema", <<'END_OF_TEXT', NO_CONTENT;
cpu,host=noauth usage_idle=77.7 1574753954000000000
END_OF_TEXT

    $result = $node->safe_psql( "postgres", <<"END_OF_SQL" );
select _time, host, usage_idle
  from $schema.cpu
 where host = 'noauth'
END_OF_SQL

    $expected = InfluxDB::Test::ResultSet->new(<<'END_OF_TEXT');
2019-11-26 07:39:14|noauth|77.7
END_OF_TEXT

    is( $result, $expected, "data inserted without auth when auth is disabled" );

    $node->stop;
}

done_testing();
