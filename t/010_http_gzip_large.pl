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
CREATE TABLE $schema.disk(_time timestamp, mode text, free integer, _tags jsonb, _fields jsonb);
END_OF_TEXT

# Generate 1000 lines of line protocol data (~80KB uncompressed, well
# above the 8KB read buffer to guarantee multiple chunked reads).
my @lines;
for my $cnt ( 0 .. 999 ) {
    my $free      = 1234 * $cnt;
    my $total     = 1024 * 1024 - $free;
    my $timestamp = 1574853954000000000 + 1000000000 * $cnt;
    push @lines,
        "disk,mode=rw,path=/boot/efi free=${free}i,total=${total}i,used_percent=1.49 $timestamp";
}

# Test 1: Large gzip-compressed body with trailing newline
{
    my $content = join( "\n", @lines ) . "\n";
    my $compressed;
    gzip \$content => \$compressed
        or die "gzip failed: $IO::Compress::Gzip::GzipError";

    cmp_ok( length($content), ">", 64 * 1024,
        "uncompressed payload with trailing newline is larger than 64 KiB" );

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
    is( $response->code, 204, "large gzip-compressed write with trailing newline returns 204" );
}

is( $node->safe_psql( "postgres", "SELECT count(*) FROM $schema.disk" ),
    1000, "large gzip body with trailing newline inserts all 1000 rows" );

# Clear table for next test
$node->safe_psql( "postgres", "TRUNCATE $schema.disk" );

# Test 2: Large gzip-compressed body without trailing newline (exercises
# on_message_complete remainder flush)
{
    my $content = join( "\n", @lines );
    my $compressed;
    gzip \$content => \$compressed
        or die "gzip failed: $IO::Compress::Gzip::GzipError";

    cmp_ok( length($content), ">", 64 * 1024,
        "uncompressed payload without trailing newline is larger than 64 KiB" );

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
    is( $response->code, 204, "large gzip-compressed write without trailing newline returns 204" );
}

is( $node->safe_psql( "postgres", "SELECT count(*) FROM $schema.disk" ),
    1000, "large gzip body without trailing newline inserts all 1000 rows" );

$node->stop;

done_testing();
