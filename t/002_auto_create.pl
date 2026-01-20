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
shared_preload_libraries = 'influxdb'
influxdb.database = 'postgres'
influxdb.schema_name = 'metrics'
influxdb.http_workers = 2
influxdb.http_service = $port
influxdb.auto_create_table = on
END_OF_TEXT

$node->start;

my $schema = $node->safe_psql( "postgres", "SHOW influxdb.schema_name" );

is( $schema, "metrics" );

$node->safe_psql( "postgres", <<"END_OF_TEXT");
CREATE EXTENSION influxdb;
CREATE SCHEMA $schema;
END_OF_TEXT

# Check that inserting into a measurement table that does not exist
# will create it.
$output = curl "http://localhost:$port/write", <<'END_OF_LINES';
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
2019-11-26 08:39:14+01|{}|{"usage": 1.2}
2019-11-26 11:25:54+01|{"kind": "i836"}|{"usage": 1.6}
END_OF_TEXT

is( $result, $expected );

$node->stop;

done_testing();
