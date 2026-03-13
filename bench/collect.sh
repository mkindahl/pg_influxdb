#!/bin/bash

# Benchmark HTTP write endpoint throughput. Generates fake InfluxDB line
# protocol data and POSTs it via curl, measuring wall-clock time per
# batch and recording results for comparison.

function usage() {
    if [[ $# -gt 0 ]]; then
	echo "error: $*" 1>&2
    fi
    cat <<EOF 1>&2
Usage: bash collect.sh [ options ]
Benchmark HTTP write endpoint throughput.

Options

    -s <scheme>    Scheme name (default: basic)
    -p <port>      HTTP listen port (default: 8086)
    -v <version>   Version label for results
    -w <workers>   Number of HTTP workers (default: 1)
    -n <count>     Number of lines per run (default: 100000)
    -b <batch>     Lines per HTTP request (default: 1000)
    -r <repeats>   Number of sample runs (default: 100)
    -h <host>      Database host (default: localhost)

EOF
    exit 2
}

function show_measurements () {
    psql -q <<EOF
SELECT version, scheme, total, count(*), avg(count::decimal), stddev(count)
  FROM measurements GROUP BY version, scheme, total
EOF
}

# Default values
HOST=${PGHOST:-localhost}
PORT=8086
WORKERS=1
SCHEME=basic
COUNT=100000
BATCH=1000
REPEATS=100

set -e

while getopts "s:p:v:w:n:b:r:h:" opt; do
    case $opt in
	s)
	    SCHEME=$OPTARG
	    ;;
	p)
	    PORT=$OPTARG
	    ;;
	v)
	    VERSION=$OPTARG
	    ;;
	w)
	    WORKERS=$OPTARG
	    ;;
	n)
	    COUNT=$OPTARG
	    ;;
	b)
	    BATCH=$OPTARG
	    ;;
	r)
	    REPEATS=$OPTARG
	    ;;
	h)
	    HOST=$OPTARG
	    ;;
	*)
	    usage
	    ;;
    esac
done

if ! [[ -r "scheme/$SCHEME.sh" ]]; then
    usage "You need to have a file scheme/$SCHEME.sh containing the scheme"
fi

# Each scheme provides: setup_scheme, reset_scheme, generate_data,
# wait_until_stable, record_measurements

# shellcheck source=scheme/basic.sh
source "scheme/$SCHEME.sh"

function influx_version() {
    # shellcheck disable=SC2046,SC2005
    echo $(psql -qt -c "select extversion from pg_extension where extname = 'influxdb'")
}

echo "Connecting to $HOST using HTTP port $PORT"

setup_scheme

VERSION=${VERSION:-$(influx_version)}

echo "Measure $COUNT lines for version '$VERSION' scheme $SCHEME"

run=0
while [ "$run" -lt "$REPEATS" ]; do
    reset_scheme

    datadir=$(mktemp -d)
    generate_data | split -l "$BATCH" - "$datadir/batch_"

    t0=$(date +%s%N)
    for batch in "$datadir"/batch_*; do
	curl -s -o /dev/null -X POST "http://$HOST:$PORT/write?db=magic" --data-binary @"$batch"
    done
    t1=$(date +%s%N)

    rm -rf "$datadir"

    elapsed_ms=$(( (t1 - t0) / 1000000 ))
    echo "Run $((run + 1))/$REPEATS: sent $COUNT lines in ${elapsed_ms}ms"

    wait_until_stable
    record_measurements
    show_measurements

    run=$((run + 1))
done
