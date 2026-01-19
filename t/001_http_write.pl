use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use Test::More;
use IPC::Run;
use HTTP::Response;
use List::Util qw(all);
use JSON       qw(decode_json);
use Data::Dumper;

sub trim { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s; }

sub curl {
    my ( $url, $input ) = @_;
    my ( $stdin, $stdout, $stderr );

    my @cmd = (
        "curl",          "-is", "--header", "Content-Type: text/plain",
        "--header",      "Connection: close",
        "--data-binary", $input, $url
    );

    IPC::Run::run \@cmd, \$stdin, \$stdout, \$stderr;
    return $stdout;
}

sub is_response {
    my ( $response, $code, $message ) = @_;
    is( $response->message, $message );
    is( $response->code,    $code );

}

sub has_headers {
    my ( $response, @headers ) = @_;
    ok( all { $response->header($_) } @headers );
}

my ( $output, $response, $json, $expected, $result );

my $node = PostgreSQL::Test::Cluster->new('main');
my $port = PostgreSQL::Test::Cluster::get_free_port();

print "Using port $port for the service\n";

$node->init;
$node->append_conf( 'postgresql.conf', <<"END_OF_TEXT");
log_min_messages = debug1
shared_preload_libraries = 'influxdb'
influxdb.database_name = 'postgres'
influxdb.schema_name = 'metrics'
influxdb.http_workers = 2
influxdb.http_service = $port
END_OF_TEXT

$node->start;

my $schema = $node->safe_psql( "postgres", "SHOW influxdb.schema_name" );

is( $schema, "metrics" );

$node->safe_psql( "postgres", <<"END_OF_TEXT");
CREATE EXTENSION influxdb;
CREATE SCHEMA $schema;
CREATE TABLE $schema.disk(_time timestamptz, mode text, free integer, _tags jsonb, _fields jsonb);
END_OF_TEXT

# Check that using the wrong endpoint will fail with an error
$output = curl "http://localhost:$port/writ", <<'END_OF_LINES';
disk,mode=rw,path=/boot/efi free=527806464i,total=0000i,used_percent=1.49 1574753954000000000
END_OF_LINES

$response = HTTP::Response->parse($output);
is_response( $response, 404, 'Not Found' );
has_headers( $response, 'Date', 'Connection' );

$output = curl "http://localhost:$port/writer", <<'END_OF_LINES';
disk,mode=rw,path=/boot/efi free=527806464i,total=0000i,used_percent=1.49 1574753954000000000
END_OF_LINES

$response = HTTP::Response->parse($output);
is_response( $response, 404, 'Not Found' );
has_headers( $response, 'Date', 'Connection' );

# Check that we get a proper response on a syntax error
$output = curl "http://localhost:$port/write", <<'END_OF_LINES';
cpu,usage=12 1574753954000000000
END_OF_LINES

$response = HTTP::Response->parse($output);
is_response( $response, 400, 'Bad Request' );
has_headers( $response, 'Date', 'Connection' );
$json = decode_json $response->content;
is( $json->{'error'}, "syntax error" );

# Check that when trying to insert into a measurement that does not
# exist generates an error.
$output = curl "http://localhost:$port/write", <<'END_OF_LINES';
cpu usage=12 1574753954000000000
END_OF_LINES

$response = HTTP::Response->parse($output);
is_response( $response, 400, 'Bad Request' );
has_headers( $response, 'Date', 'Connection' );
$json = decode_json $response->content;
is( $json->{'error'}, q/no relation "cpu" found in namespace "metrics"/ );

# Check that we can write data through the endpoint and get the right
# result.
$output = curl "http://localhost:$port/write", <<'END_OF_LINES';
disk,mode=rw,path=/boot/efi free=527806464i,total=0000i,used_percent=1.49 1574753954000000000
disk,mode=rw,path=/boot/efi free=527807775i,total=1000i,used_percent=1.12 1574753964000000000
disk,mode=rw,path=/boot/efi free=527808830i,total=2000i,used_percent=1.11 1574753974000000000
disk,mode=rw,path=/boot/efi free=527809294i,total=3000i,used_percent=20.3 1574753984000000000
disk,mode=rw,path=/boot/efi free=527806464i,total=4000i,used_percent=1.49 1574753994000000000
END_OF_LINES

$response = HTTP::Response->parse($output);
is_response( $response, 204, 'No Content' );
has_headers( $response, 'Date' );

$result = $node->safe_psql( "postgres", <<"END_OF_SQL" );
select * from $schema.disk order by _time;
END_OF_SQL

$expected = trim(<<'END_OF_TEXT');
2019-11-26 08:39:14+01|rw|527806464|{"path": "/boot/efi"}|{"total": 0, "used_percent": 1.49}
2019-11-26 08:39:24+01|rw|527807775|{"path": "/boot/efi"}|{"total": 1000, "used_percent": 1.12}
2019-11-26 08:39:34+01|rw|527808830|{"path": "/boot/efi"}|{"total": 2000, "used_percent": 1.11}
2019-11-26 08:39:44+01|rw|527809294|{"path": "/boot/efi"}|{"total": 3000, "used_percent": 20.3}
2019-11-26 08:39:54+01|rw|527806464|{"path": "/boot/efi"}|{"total": 4000, "used_percent": 1.49}
END_OF_TEXT

is( $result, $expected );

# Check that write endpoint is handled correctly even when we have
# parameters in the URL. Databases are not used yet, but it should
# work anyway.
$output = curl "http://localhost:$port/write?db=mydb", <<'END_OF_LINES';
disk,mode=rw,path=/boot/efi free=527806464i,total=0000i,used_percent=1.49 1574853954000000000
disk,mode=rw,path=/boot/efi free=527807775i,total=1000i,used_percent=1.12 1574853964000000000
END_OF_LINES

$response = HTTP::Response->parse($output);
is_response( $response, 204, 'No Content' );
has_headers( $response, 'Date' );

$result = $node->safe_psql( "postgres", <<"END_OF_SQL" );
select * from $schema.disk where _time > '2019-11-27 00:00:00' order by _time;
END_OF_SQL

$expected = trim(<<'END_OF_TEXT');
2019-11-27 12:25:54+01|rw|527806464|{"path": "/boot/efi"}|{"total": 0, "used_percent": 1.49}
2019-11-27 12:26:04+01|rw|527807775|{"path": "/boot/efi"}|{"total": 1000, "used_percent": 1.12}
END_OF_TEXT

is( $result, $expected );

done_testing();
