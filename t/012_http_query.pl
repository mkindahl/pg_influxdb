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

# Test without auth
{
    my $node = InfluxDB::Test::Cluster->new('query_noauth');
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

    # Test: CREATE DATABASE creates a schema
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [
            "curl", "-is", "--header", "Connection: close",
            "--data",
            "q=CREATE+DATABASE+%22newschema%22",
            "http://localhost:$port/query"
            ],
            \$stdin, \$stdout, \$stderr;

        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 200, "CREATE DATABASE returns 200" );
        is( $response->header('Content-Type'),
            'application/json', "Content-Type is application/json" );
        like( $response->content, qr/\{"results":\[\{\}\]\}/, "response body is correct" );
    }

    # Verify schema exists
    {
        my $result = $node->safe_psql( "postgres",
            "SELECT 1 FROM pg_namespace WHERE nspname = 'newschema'" );
        is( $result, "1", "schema 'newschema' was created" );
    }

    # Test: idempotent — same CREATE DATABASE again
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [
            "curl", "-is", "--header", "Connection: close",
            "--data",
            "q=CREATE+DATABASE+%22newschema%22",
            "http://localhost:$port/query"
            ],
            \$stdin, \$stdout, \$stderr;

        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 200, "idempotent CREATE DATABASE returns 200" );
    }

    # Test: missing q parameter
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [
            "curl",   "-is",     "--header", "Connection: close",
            "--data", "foo=bar", "http://localhost:$port/query"
            ],
            \$stdin, \$stdout, \$stderr;

        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 400, "missing q parameter returns 400" );
        like(
            $response->content,
            qr/missing required parameter/,
            "error mentions missing parameter"
        );
    }

    # Test: bare percent sign in query body
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [
            "curl",   "-is", "--header", "Connection: close",
            "--data", "q=%", "http://localhost:$port/query"
            ],
            \$stdin, \$stdout, \$stderr;

        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 400, "bare percent returns 400" );
    }

    # Test: truncated percent-encoding with one hex digit
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [
            "curl",   "-is",  "--header", "Connection: close",
            "--data", "q=%f", "http://localhost:$port/query"
            ],
            \$stdin, \$stdout, \$stderr;

        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 400, "truncated percent-encoding returns 400" );
    }

    # Test: valid percent-encoding of non-ASCII byte
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [
            "curl",   "-is",   "--header", "Connection: close",
            "--data", "q=%ff", "http://localhost:$port/query"
            ],
            \$stdin, \$stdout, \$stderr;

        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 400, "percent-encoded non-ASCII byte returns 400" );
    }

    # Test: unterminated quoted database name
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [
            "curl", "-is", "--header", "Connection: close",
            "--data",
            "q=CREATE+DATABASE+%22unterminated",
            "http://localhost:$port/query"
            ],
            \$stdin, \$stdout, \$stderr;

        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 400, "unterminated quoted name returns 400" );
        like(
            $response->content,
            qr/EOF in string literal/,
            "error mentions EOF in string literal"
        );
    }

    # Test: unrecognized query
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [
            "curl",   "-is",        "--header", "Connection: close",
            "--data", "q=SELECT+1", "http://localhost:$port/query"
            ],
            \$stdin, \$stdout, \$stderr;

        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 400, "unrecognized query returns 400" );
        like( $response->content, qr/syntax error/, "error mentions syntax error" );
    }

    $node->stop;
}

# Test with auth configured
{
    my $node = InfluxDB::Test::Cluster->new('query_auth');
    my $port = PostgreSQL::Test::Cluster::get_free_port();

    my $username = "influx_user";
    my $password = "influx_pass";

    $node->init;
    $node->append_conf( 'postgresql.conf', <<"END_OF_TEXT");
shared_preload_libraries = 'influxdb'
influxdb.database = 'postgres'
influxdb.http_workers = 2
influxdb.http_service = $port
influxdb.http_auth = on
END_OF_TEXT

    $node->start;

    $node->safe_psql( "postgres", <<"END_OF_TEXT");
CREATE USER $username WITH PASSWORD '$password';
CREATE EXTENSION influxdb;
END_OF_TEXT

    # Test: no credentials -> 401
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [
            "curl", "-is", "--header", "Connection: close",
            "--data",
            "q=CREATE+DATABASE+%22authdb%22",
            "http://localhost:$port/query"
            ],
            \$stdin, \$stdout, \$stderr;

        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 401, "/query without credentials returns 401" );
    }

    # Test: valid credentials -> 200
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [
            "curl", "-is", "-u", "$username:$password", "--header", "Connection: close",
            "--data",
            "q=CREATE+DATABASE+%22authdb%22",
            "http://localhost:$port/query"
            ],
            \$stdin, \$stdout, \$stderr;

        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 200, "/query with valid credentials returns 200" );
    }

    # Verify schema exists
    {
        my $result =
            $node->safe_psql( "postgres", "SELECT 1 FROM pg_namespace WHERE nspname = 'authdb'" );
        is( $result, "1", "schema 'authdb' was created with auth" );
    }

    $node->stop;
}

done_testing();
