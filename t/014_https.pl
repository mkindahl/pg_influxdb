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

# Skip the entire test file if influxdb was compiled without SSL support.
{
    my $pkglibdir = `pg_config --pkglibdir`;
    chomp $pkglibdir;
    my $so      = "$pkglibdir/influxdb.so";
    my $has_ssl = ( -f $so && system("ldd '$so' 2>/dev/null | grep -q ssl") == 0 );
    plan skip_all => "influxdb was compiled without SSL support"
        unless $has_ssl;
}

# Skip the entire test file if openssl(1) is not available.
{
    my ( $stdin, $stdout, $stderr );
    IPC::Run::run [ "openssl", "version" ], \$stdin, \$stdout, \$stderr
        or plan skip_all => "openssl binary not found";
}

my $schema = "metrics";

# -----------------------------------------------------------------------
# Block 1: influxdb.https = on
# -----------------------------------------------------------------------
{
    my $node = InfluxDB::Test::Cluster->new('https_on');
    my $port = PostgreSQL::Test::Cluster::get_free_port();

    $node->init;

    # Generate a self-signed certificate in the data directory.  The
    # paths match the postgresql ssl_cert_file / ssl_key_file defaults
    # so no extra GUCs are needed.
    my $data_dir  = $node->data_dir;
    my $cert_file = "$data_dir/server.crt";
    my $key_file  = "$data_dir/server.key";

    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [
            "openssl", "req",   "-newkey", "rsa:2048", "-nodes", "-keyout",
            $key_file, "-x509", "-days",   "1",        "-out",   $cert_file,
            "-subj",   "/CN=localhost",
            ],
            \$stdin, \$stdout, \$stderr
            or die "openssl req failed: $stderr";
    }
    chmod 0600, $key_file;

    $node->append_conf( 'postgresql.conf', <<"END_OF_TEXT");
shared_preload_libraries = 'influxdb'
influxdb.database = 'postgres'
influxdb.http_workers = 2
influxdb.http_service = $port
influxdb.https = on
END_OF_TEXT

    $node->start;

    $node->safe_psql( "postgres", <<"END_OF_SQL");
CREATE EXTENSION influxdb;
CREATE SCHEMA $schema;
CREATE TABLE $schema.cpu(_time timestamp, host text, usage_idle float8, _tags jsonb, _fields jsonb);
END_OF_SQL

    # Test: /ping over HTTPS returns 204
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [ "curl", "-is", "--cacert", $cert_file, "https://localhost:$port/ping", ],
            \$stdin, \$stdout, \$stderr;

        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 204, "HTTPS /ping returns 204" );
        is( $response->header('X-Influxdb-Version'),
            'pg_influxdb', "HTTPS /ping returns X-Influxdb-Version header" );
    }

    # Test: /write over HTTPS inserts data
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [
            "curl",
            "-is",
            "--cacert",
            $cert_file,
            "--header",
            "Content-Type: text/plain",
            "--header",
            "Connection: close",
            "--data-binary",
            "cpu,host=https_host usage_idle=99.5 1574753954000000000",
            "https://localhost:$port/write?db=$schema",
            ],
            \$stdin, \$stdout, \$stderr;

        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 204, "HTTPS /write returns 204" );
    }

    my $result = $node->safe_psql( "postgres", <<"END_OF_SQL");
SELECT _time, host, usage_idle FROM $schema.cpu WHERE host = 'https_host'
END_OF_SQL

    my $expected = InfluxDB::Test::ResultSet->new(<<'END_OF_TEXT');
2019-11-26 07:39:14|https_host|99.5
END_OF_TEXT

    is( $result, $expected, "data written over HTTPS is stored correctly" );

    # Test: plain HTTP client connecting to the HTTPS port does not get
    # a valid HTTP response (the TLS layer rejects the unencrypted request).
    {
        my ( $stdin, $stdout, $stderr );
        my $ok = IPC::Run::run [ "curl", "-is", "--max-time", "5", "http://localhost:$port/ping", ],
            \$stdin, \$stdout, \$stderr;

        ok( !$ok, "plain HTTP connection to HTTPS port fails" );
    }

    # Test: curl with the wrong CA certificate fails to verify the server.
    {
        # Generate a second, unrelated CA cert that the server was not
        # signed by.
        my $wrong_ca = "$data_dir/wrong_ca.crt";
        {
            my ( $stdin, $stdout, $stderr );
            IPC::Run::run [
                "openssl", "req", "-newkey", "rsa:2048", "-nodes",
                "-keyout", "$data_dir/wrong_ca.key", "-x509", "-days", "1", "-out", $wrong_ca,
                "-subj",   "/CN=wrong-ca",
                ],
                \$stdin, \$stdout, \$stderr
                or die "openssl req (wrong CA) failed: $stderr";
        }

        my ( $stdin, $stdout, $stderr );
        my $ok =
            IPC::Run::run [ "curl", "-is", "--cacert", $wrong_ca, "https://localhost:$port/ping", ],
            \$stdin, \$stdout, \$stderr;

        ok( !$ok, "connection with wrong CA certificate is rejected by curl" );
    }

    # Test: TLS 1.2 handshake succeeds.
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [ "openssl", "s_client", "-connect", "localhost:$port", "-tls1_2", ],
            \"", \$stdout, \$stderr;

        like( $stdout . $stderr, qr/CONNECTED/, "TLS 1.2 handshake succeeds" );
    }

    # Test: TLS 1.3 handshake succeeds (if the client supports it).
SKIP: {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [ "openssl", "s_client", "-connect", "localhost:$port", "-tls1_3", ],
            \"", \$stdout, \$stderr;

        # Older openssl builds do not understand -tls1_3; skip gracefully.
        skip "openssl does not support -tls1_3", 1
            if $stdout . $stderr =~ /unknown option/i;

        like( $stdout . $stderr, qr/CONNECTED/, "TLS 1.3 handshake succeeds" );
    }

    $node->stop;
}

# -----------------------------------------------------------------------
# Block 2: HTTP and HTTPS simultaneously on separate ports
# -----------------------------------------------------------------------
{
    my $node       = InfluxDB::Test::Cluster->new('dual_listener');
    my $http_port  = PostgreSQL::Test::Cluster::get_free_port();
    my $https_port = PostgreSQL::Test::Cluster::get_free_port();

    $node->init;

    my $data_dir  = $node->data_dir;
    my $cert_file = "$data_dir/server.crt";
    my $key_file  = "$data_dir/server.key";

    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [
            "openssl", "req",   "-newkey", "rsa:2048", "-nodes", "-keyout",
            $key_file, "-x509", "-days",   "1",        "-out",   $cert_file,
            "-subj",   "/CN=localhost",
            ],
            \$stdin, \$stdout, \$stderr
            or die "openssl req failed: $stderr";
    }
    chmod 0600, $key_file;

    $node->append_conf( 'postgresql.conf', <<"END_OF_TEXT");
shared_preload_libraries = 'influxdb'
influxdb.database = 'postgres'
influxdb.http_workers = 2
influxdb.http_service = $http_port
influxdb.https_service = $https_port
END_OF_TEXT

    $node->start;

    $node->safe_psql( "postgres", <<"END_OF_SQL");
CREATE EXTENSION influxdb;
CREATE SCHEMA $schema;
CREATE TABLE $schema.cpu(_time timestamp, host text, usage_idle float8, _tags jsonb, _fields jsonb);
END_OF_SQL

    # Test: HTTP listener still answers plain requests
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [ "curl", "-is", "http://localhost:$http_port/ping" ],
            \$stdin, \$stdout, \$stderr;
        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 204, "dual-listener: HTTP /ping returns 204" );
    }

    # Test: HTTPS listener answers TLS requests on the separate port
    {
        my ( $stdin, $stdout, $stderr );
        IPC::Run::run [ "curl", "-is", "--cacert", $cert_file, "https://localhost:$https_port/ping",
            ],
            \$stdin, \$stdout, \$stderr;
        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 204, "dual-listener: HTTPS /ping returns 204" );
    }

    # Test: write via HTTP and read via HTTPS see the same data
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
            "cpu,host=dual_host usage_idle=55.5 1574753954000000000",
            "http://localhost:$http_port/write?db=$schema",
            ],
            \$stdin, \$stdout, \$stderr;
        my $response = HTTP::Response->parse($stdout);
        is( $response->code, 204, "dual-listener: HTTP /write returns 204" );
    }

    my $result = $node->safe_psql( "postgres", <<"END_OF_SQL");
SELECT _time, host, usage_idle FROM $schema.cpu WHERE host = 'dual_host'
END_OF_SQL

    my $expected = InfluxDB::Test::ResultSet->new(<<'END_OF_TEXT');
2019-11-26 07:39:14|dual_host|55.5
END_OF_TEXT

    is( $result, $expected, "dual-listener: data written over HTTP is visible from HTTPS side" );

    # Test: plain HTTP on the HTTPS port still fails
    {
        my ( $stdin, $stdout, $stderr );
        my $ok =
            IPC::Run::run [ "curl", "-is", "--max-time", "5",
            "http://localhost:$https_port/ping", ],
            \$stdin, \$stdout, \$stderr;
        ok( !$ok, "dual-listener: plain HTTP on HTTPS port fails" );
    }

    $node->stop;
}

# -----------------------------------------------------------------------
# Block 3: influxdb.https = off (default) – plain HTTP must still work
# -----------------------------------------------------------------------
{
    my $node = InfluxDB::Test::Cluster->new('https_off');
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

    my ( $stdin, $stdout, $stderr );
    IPC::Run::run [ "curl", "-is", "http://localhost:$port/ping" ], \$stdin, \$stdout, \$stderr;

    my $response = HTTP::Response->parse($stdout);
    is( $response->code, 204, "plain HTTP /ping still works when HTTPS is off" );

    $node->stop;
}

done_testing();
