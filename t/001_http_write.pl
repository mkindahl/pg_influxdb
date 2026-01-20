use strict;
#use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use Test::More;
use IPC::Run;
use HTTP::Response;
use List::Util qw(all);
use JSON       qw(decode_json);
use Data::Dumper;

use constant {
    NO_CONTENT  => 204,
    BAD_REQUEST => 400,
    NOT_FOUND   => 404,
};

my %reason = (
    204  => 'No Content',
    400 => 'Bad Request',
    404   => 'Not Found',
);

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
    my $tb = Test::More->builder;

    $tb->is_eq( $response->message, $message );
    $tb->is_eq( $response->code,    $code );

}

sub has_headers {
    my ( $response, @headers ) = @_;
    my $tb = Test::More->builder;
    $tb->ok( all { $response->header($_) } @headers );
}

sub test_endpoint {
    my ( $endpoint, $input, $code, $check ) = @_;
    my $reason   = $reason{$code};
    my $output   = curl $endpoint, $input;
    my $response = HTTP::Response->parse($output);
    my $tb = Test::More->builder;
    my @headers = ('Date', 'Connection');

    $tb->ok( all { $response->header($_) } @headers );
    $tb->is_eq( $response->message, $reason );
    $tb->is_eq( $response->code,    $code );
    $check->($response) if defined $check;
}

sub has_error {
    my ($error) = @_;
    my $func = sub {
        my ($response) = @_;
        my $tb = Test::More->builder;
        my $json = decode_json( $response->content );
        return $tb->like( $json->{'error'}, $error );
    };
    return $func;
}

my ( $output, $response, $json, $expected, $result );

my $syntax_error = has_error(qr/syntax error/);
my $table_missing = has_error(qr/no relation "\w+" found in namespace "\w+"/);
my $node         = PostgreSQL::Test::Cluster->new('main');
my $port         = PostgreSQL::Test::Cluster::get_free_port();

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
CREATE TABLE $schema.disk(_time timestamptz, mode text, free integer, _tags jsonb, _fields jsonb);
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
2019-11-26 08:39:14+01|rw|527806464|{"path": "/boot/efi"}|{"total": 0, "used_percent": 1.49}
2019-11-26 08:39:34+01|rw|527808830|{"path": "/boot/efi"}|{"total": 2000, "used_percent": 1.11}
2019-11-26 08:39:54+01|rw|527806464|{"path": "/boot/efi"}|{"total": 4000, "used_percent": 1.49}
END

is( $result, $expected );

# Check that write endpoint is handled correctly even when we have
# unrecognized parameters in the URL.
test_endpoint "http://localhost:$port/write?db=metrics&magic=more", <<'END', NO_CONTENT;
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
2019-11-27 12:25:54+01|rw|527806464|{"path": "/boot/efi"}|{"total": 0, "used_percent": 1.49}
2019-11-27 12:26:04+01|rw|527807775|{"path": "/boot/efi"}|{"total": 1000, "used_percent": 1.12}
END_OF_TEXT

is( $result, $expected );

$node->stop;

done_testing();
