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
use IO::Compress::Gzip qw(gzip);
use File::Temp         qw(tempfile);

my ( $result, $expected );

my $node   = InfluxDB::Test::Cluster->new('main');
my $port   = PostgreSQL::Test::Cluster::get_free_port();
my $schema = "metrics";

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

# Test gzip-compressed write
{
    my $line_protocol = "cpu,host=gziphost usage_idle=42.5 1574753954000000000\n";
    my $compressed;
    gzip \$line_protocol => \$compressed
        or die "gzip failed: $IO::Compress::Gzip::GzipError";

    # Write compressed data to a temp file for curl
    my ( $fh, $tmpfile ) = tempfile( UNLINK => 1 );
    binmode $fh;
    print $fh $compressed;
    close $fh;

    my ( $stdin, $stdout, $stderr );
    IPC::Run::run [
        "curl",          "-is",
        "--header",      "Content-Encoding: gzip",
        "--header",      "Content-Type: application/octet-stream",
        "--header",      "Connection: close",
        "--data-binary", "\@$tmpfile",
        "http://localhost:$port/write?db=$schema"
        ],
        \$stdin, \$stdout, \$stderr;

    my $response = HTTP::Response->parse($stdout);
    is( $response->code, 204, "gzip-compressed write returns 204" );
}

$result = $node->safe_psql( "postgres", <<"END_OF_SQL" );
select _time, host, usage_idle
  from $schema.cpu
 where host = 'gziphost'
END_OF_SQL

$expected = InfluxDB::Test::ResultSet->new(<<'END_OF_TEXT');
2019-11-26 07:39:14|gziphost|42.5
END_OF_TEXT

is( $result, $expected, "gzip-compressed data was inserted correctly" );

# Test gzip with precision=s
{
    my $line_protocol = "cpu,host=gziphost2 usage_idle=33.3 1574753964\n";
    my $compressed;
    gzip \$line_protocol => \$compressed
        or die "gzip failed: $IO::Compress::Gzip::GzipError";

    my ( $fh, $tmpfile ) = tempfile( UNLINK => 1 );
    binmode $fh;
    print $fh $compressed;
    close $fh;

    my ( $stdin, $stdout, $stderr );
    IPC::Run::run [
        "curl",
        "-is",
        "--header",
        "Content-Encoding: gzip",
        "--header",
        "Content-Type: application/octet-stream",
        "--header",
        "Connection: close",
        "--data-binary",
        "\@$tmpfile",
        "http://localhost:$port/write?db=$schema&precision=s"
        ],
        \$stdin, \$stdout, \$stderr;

    my $response = HTTP::Response->parse($stdout);
    is( $response->code, 204, "gzip-compressed write with precision=s returns 204" );
}

$result = $node->safe_psql( "postgres", <<"END_OF_SQL" );
select _time, host, usage_idle
  from $schema.cpu
 where host = 'gziphost2'
END_OF_SQL

$expected = InfluxDB::Test::ResultSet->new(<<'END_OF_TEXT');
2019-11-26 07:39:24|gziphost2|33.3
END_OF_TEXT

is( $result, $expected, "gzip-compressed data with precision=s was inserted correctly" );

$node->stop;

done_testing();
