#!/bin/bash
# InfluxDB API to PostgreSQL — Docker entrypoint init script
#
# Runs once on first container start via /docker-entrypoint-initdb.d/.
# Configures postgresql.conf GUCs from environment variables and creates
# the extension in the target database.

set -e

: "${INFLUXDB_DATABASE:=postgres}"
: "${INFLUXDB_HTTP_PORT:=8086}"
: "${INFLUXDB_HTTP_WORKERS:=4}"
: "${INFLUXDB_HTTP_AUTH:=off}"
: "${INFLUXDB_UDP_PORT:=8089}"
: "${INFLUXDB_UDP_WORKERS:=4}"
: "${INFLUXDB_UDP_SCHEMA:=measurements}"
: "${INFLUXDB_AUTO_CREATE_TABLE:=on}"

# --- shared_preload_libraries -------------------------------------------

if grep -q "^shared_preload_libraries" "$PGDATA/postgresql.conf" 2>/dev/null; then
    sed -i "s/^shared_preload_libraries = '\(.*\)'/shared_preload_libraries = '\1,influxdb'/" \
        "$PGDATA/postgresql.conf"
else
    echo "shared_preload_libraries = 'influxdb'" >> "$PGDATA/postgresql.conf"
fi

# --- influxdb GUCs ------------------------------------------------------

cat >> "$PGDATA/postgresql.conf" <<EOF

# pg_influxdb settings (Docker)
max_worker_processes = 16
influxdb.database = '${INFLUXDB_DATABASE}'
influxdb.http_service = '${INFLUXDB_HTTP_PORT}'
influxdb.http_workers = ${INFLUXDB_HTTP_WORKERS}
influxdb.http_auth = ${INFLUXDB_HTTP_AUTH}
influxdb.udp_service = '${INFLUXDB_UDP_PORT}'
influxdb.udp_workers = ${INFLUXDB_UDP_WORKERS}
influxdb.udp_schema = '${INFLUXDB_UDP_SCHEMA}'
influxdb.auto_create_table = ${INFLUXDB_AUTO_CREATE_TABLE}
EOF

# --- Create database if needed ------------------------------------------

target_db="${INFLUXDB_DATABASE}"
if [ "$target_db" != "${POSTGRES_DB:-postgres}" ]; then
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "${POSTGRES_DB:-postgres}" <<-EOSQL
        SELECT 'CREATE DATABASE ${target_db}'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${target_db}')\gexec
EOSQL
fi

# --- Create extension ---------------------------------------------------

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$target_db" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS influxdb;
EOSQL
