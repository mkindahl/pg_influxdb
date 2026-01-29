package InfluxDB::Extras;

use parent 'Exporter';

our @EXPORT_OK =
  qw(trim curl is_response has_headers has_error test_endpoint NO_CONTENT BAD_REQUEST NOT_FOUND);
our %EXPORT_TAGS = (
    'constants' => [ 'NO_CONTENT', 'BAD_REQUEST', 'NOT_FOUND' ],
    'utils'     => [ 'trim',       'curl' ],
    'http' => [ 'is_response', 'has_headers', 'has_error', 'test_endpoint' ],
);

use Test::More;
use HTTP::Response;
use JSON       qw(decode_json);
use List::Util qw(all);
use IPC::Run;

use constant {
    NO_CONTENT  => 204,
    BAD_REQUEST => 400,
    NOT_FOUND   => 404,
};

my %reason = (
    204 => 'No Content',
    400 => 'Bad Request',
    404 => 'Not Found',
);

sub trim {
    my $s = shift;
    $s =~ s/^\s+|\s+$//g;
    return $s;
}

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
    my $tb       = Test::More->builder;
    my @headers  = ( 'Date', 'Connection' );
    my $json     = decode_json( $response->content ) if $response->content;
    my $errmsg   = "generated error '" . $json->{'error'} . "'"
      if $response->content;

    $tb->ok( all { $response->header($_) } @headers );
    $tb->is_eq( $response->message, $reason, $errmsg );
    $tb->is_eq( $response->code,    $code,   $errmsg );
    $check->($response) if defined $check;
}

sub has_error {
    my ($error) = @_;
    my $func = sub {
        my ($response) = @_;
        my $tb         = Test::More->builder;
        my $json       = decode_json( $response->content );
        return $tb->like( $json->{'error'}, $error );
    };
    return $func;
}

my %seen;

push @{ $EXPORT_TAGS{all} }, grep { !$seen{$_}++ } @{ $EXPORT_TAGS{$_} }
  foreach keys %EXPORT_TAGS;

1;
