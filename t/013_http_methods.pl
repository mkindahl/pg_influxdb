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
use HTTP::Response;
use IPC::Run;

# /write: only POST allowed
sub test_write_method {
    my ($port) = @_;
    my ( $response, $stdin, $stdout, $stderr );

    # GET /write -> 405
    IPC::Run::run [
        "curl", "-is", "--header",
        "Connection: close",
        "http://localhost:$port/write?db=postgres"
        ],
        \$stdin, \$stdout, \$stderr;

    $response = HTTP::Response->parse($stdout);
    is( $response->code,            405,    "GET /write returns 405" );
    is( $response->header('Allow'), "POST", "/write Allow header is POST" );
    like( $response->content, qr/method not allowed/, "error mentions method not allowed" );

    # DELETE /write -> 405
    IPC::Run::run [
        "curl", "-is", "-X", "DELETE", "--header",
        "Connection: close",
        "http://localhost:$port/write?db=postgres"
        ],
        \$stdin, \$stdout, \$stderr;

    $response = HTTP::Response->parse($stdout);
    is( $response->code, 405, "DELETE /write returns 405" );
}

# /ping: GET and HEAD allowed
sub test_ping_method {
    my ($port) = @_;
    my ( $response, $stdin, $stdout, $stderr );

    # GET /ping -> 204
    IPC::Run::run [ "curl", "-is", "--header", "Connection: close", "http://localhost:$port/ping" ],
        \$stdin, \$stdout, \$stderr;

    $response = HTTP::Response->parse($stdout);
    is( $response->code, 204, "GET /ping returns 204" );

    # HEAD /ping -> 204
    IPC::Run::run [ "curl", "-is", "--head", "--header", "Connection: close",
        "http://localhost:$port/ping" ],
        \$stdin, \$stdout, \$stderr;

    $response = HTTP::Response->parse($stdout);
    is( $response->code, 204, "HEAD /ping returns 204" );

    # POST /ping -> 405
    IPC::Run::run [
        "curl", "-is", "-X", "POST", "--header", "Connection: close",
        "http://localhost:$port/ping"
        ],
        \$stdin, \$stdout, \$stderr;

    $response = HTTP::Response->parse($stdout);
    is( $response->code,            405,         "POST /ping returns 405" );
    is( $response->header('Allow'), "GET, HEAD", "/ping Allow header is GET, HEAD" );
}

# /query: POST and GET allowed
sub test_query_method {
    my ($port) = @_;
    my ( $response, $stdin, $stdout, $stderr );

    # DELETE /query -> 405
    IPC::Run::run [
        "curl", "-is", "-X", "DELETE", "--header",
        "Connection: close",
        "http://localhost:$port/query"
        ],
        \$stdin, \$stdout, \$stderr;

    $response = HTTP::Response->parse($stdout);
    is( $response->code,            405,         "DELETE /query returns 405" );
    is( $response->header('Allow'), "GET, POST", "/query Allow header is GET, POST" );
}

my $node = InfluxDB::Test::Cluster->new('methods');
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

test_write_method($port);
test_ping_method($port);
test_query_method($port);

$node->stop;

done_testing();
