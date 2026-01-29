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

my $syntax_error  = has_error(qr/syntax error/);
my $table_missing = has_error(qr/no relation "\w+" found in namespace "\w+"/);
my $node          = PostgreSQL::Test::Cluster->new('main');
my $port          = PostgreSQL::Test::Cluster::get_free_port();

print "Using port $port for the service\n";

$node->init;
$node->append_conf( 'postgresql.conf', <<"END_OF_TEXT");
log_min_messages = debug1
shared_preload_libraries = 'influxdb'
influxdb.database = 'postgres'
influxdb.http_workers = 2
influxdb.http_service = $port
END_OF_TEXT

$node->start;

my $schema = "metrics";

$node->safe_psql( "postgres", <<"END_OF_TEXT");
CREATE EXTENSION influxdb;
CREATE SCHEMA $schema;
CREATE TABLE $schema.disk(_time timestamp, mode text, free integer, _tags jsonb, _fields jsonb);
END_OF_TEXT

# Check that using the wrong endpoint will fail with an error
test_endpoint "http://localhost:$port/writ", <<'END', NOT_FOUND;
disk,mode=rw,path=/boot/efi free=527806464i,total=0000i,used_percent=1.49 1574753954000000000
END

test_endpoint "http://localhost:$port/writer", <<'END', NOT_FOUND;
disk,mode=rw,path=/boot/efi free=527806464i,total=0000i,used_percent=1.49 1574753954000000000
END

# Check that we get a proper response on a syntax error
test_endpoint "http://localhost:$port/write",
  <<'END', BAD_REQUEST, $syntax_error;
cpu,usage=12 1574753954000000000
END

# Check that when trying to insert into a measurement that does not
# exist generates an error.
test_endpoint "http://localhost:$port/write?db=$schema",
  <<'END', BAD_REQUEST, $table_missing;
cpu usage=1.22 1574753954000000000
END

# Check that we can write data through the endpoint and get the right
# result. Note that this involves lines that do not have a timestamp,
# and these should be added but will have the server timestamp.
test_endpoint "http://localhost:$port/write?db=$schema", <<'END', NO_CONTENT;
disk,mode=rw,path=/boot/efi free=527806464i,total=0000i,used_percent=1.49 1574753954000000000
disk,mode=rw,path=/boot/efi free=527807775i,total=1000i,used_percent=1.12
disk,mode=rw,path=/boot/efi free=527808830i,total=2000i,used_percent=1.11 1574753974000000000
disk,mode=rw,path=/boot/efi free=527809294i,total=3000i,used_percent=20.3
disk,mode=rw,path=/boot/efi free=527806464i,total=4000i,used_percent=1.49 1574753994000000000
END

is( $node->safe_psql( "postgres", "select count(*) from $schema.disk" ), 5 );

$result = $node->safe_psql( "postgres", <<"END" );
select *
  from $schema.disk
 where _time between '2019-11-26 00:00:00'
                 and '2019-11-27 00:00:00'
order by _time;
END

$expected = trim(<<'END');
2019-11-26 07:39:14|rw|527806464|{"path": "/boot/efi"}|{"total": 0, "used_percent": 1.49}
2019-11-26 07:39:34|rw|527808830|{"path": "/boot/efi"}|{"total": 2000, "used_percent": 1.11}
2019-11-26 07:39:54|rw|527806464|{"path": "/boot/efi"}|{"total": 4000, "used_percent": 1.49}
END

is( $result, $expected );

# Check that write endpoint is handled correctly even when we have
# unrecognized parameters in the URL.
test_endpoint "http://localhost:$port/write?db=metrics&m=m",
  <<'END', NO_CONTENT;
disk,mode=rw,path=/boot/efi free=527806464i,total=0000i,used_percent=1.49 1574853954000000000
disk,mode=rw,path=/boot/efi free=527807775i,total=1000i,used_percent=1.12 1574853964000000000
END

$result = $node->safe_psql( "postgres", <<"END_OF_SQL" );
select *
  from $schema.disk
 where _time between '2019-11-27 00:00:00'
                 and '2019-11-28 00:00:00'
order by _time;
END_OF_SQL

$expected = trim(<<'END_OF_TEXT');
2019-11-27 11:25:54|rw|527806464|{"path": "/boot/efi"}|{"total": 0, "used_percent": 1.49}
2019-11-27 11:26:04|rw|527807775|{"path": "/boot/efi"}|{"total": 1000, "used_percent": 1.12}
END_OF_TEXT

is( $result, $expected );

# Build a very large request (larger than 8KiB, which is the limit of
# the buffer for reading data). This will force the read to be split
# into multiple pieces, and we expect all to be handled.
my @lines;
for my $cnt ( 0 .. 100 ) {
    my $free      = 1234 * $cnt;
    my $total     = 1024 * 1024 - $free;
    my $timestamp = 1574853954000000000 + 1000 * $cnt;
    push @lines,
"disk,mode=rw,path=/boot/efi free=${free}i,total=${total}i,used_percent=1.49 $timestamp";
}

my $content = join "\n", @lines;
print STDERR "length of contents is ", length($content) / 1024, " KiB\n";
print STDERR $content;

test_endpoint "http://localhost:$port/write?db=metrics", $content, NO_CONTENT;

$node->stop;

done_testing();
