use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use Test::More;
use IPC::Run;
use HTTP::Response;

sub curl {
    my ( $url, $input ) = @_;
    my ( $stdout, $stderr );

    my @cmd = (
        "curl",          "-is",
        "--request",     "POST",
        "--header",      "Content-Type: application/octet-stream",
        "--header",      "Connection: close",
        "--data-binary", "@-",
        $url
    );

    IPC::Run::run \@cmd, \$input, \$stdout, \$stderr ;

    return $stdout;
}

my $node = PostgreSQL::Test::Cluster->new('main');

my $port = PostgreSQL::Test::Cluster::get_free_port();

print "Using port $port for the service\n";

$node->init( 'auth_extra' => [ '--create-role', 'test_user' ] );
$node->append_conf( 'postgresql.conf', <<"END_OF_TEXT");
shared_preload_libraries = 'influxdb'
influxdb.database_name = 'postgres'
influxdb.schema_name = 'metrics'
influxdb.http_workers = 2
influxdb.http_service = $port
END_OF_TEXT

$node->start;

my $schema = $node->safe_psql( "postgres", "SHOW influxdb.schema_name" );

is( $schema, "metrics" );

$node->safe_psql( "postgres", <<'END_OF_TEXT');
CREATE EXTENSION influxdb;
CREATE SCHEMA metric;
CREATE TABLE metric.disk(_time timestamptz, mode text, free integer, _tags jsonb, _fields jsonb);
END_OF_TEXT

my $stdout = curl "http://localhost:$port/write", <<'END_OF_LINES';
disk,mode=rw,path=/boot/efi free=527806464i,total=0000i,used_percent=1.49 1574753954000000000
disk,mode=rw,path=/boot/efi free=527807775i,total=1000i,used_percent=1.12 1574753964000000000
disk,mode=rw,path=/boot/efi free=527808830i,total=2000i,used_percent=1.11 1574753974000000000
disk,mode=rw,path=/boot/efi free=527809294i,total=3000i,used_percent=20.3 1574753984000000000
disk,mode=rw,path=/boot/efi free=527806464i,total=4000i,used_percent=1.49 1574753994000000000
END_OF_LINES

my $response = HTTP::Response->parse($stdout);

is( $response->message, 'No Content' );
is( $response->code,    204 );
ok( $response->header('Date') );

done_testing();
