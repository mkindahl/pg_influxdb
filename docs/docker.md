# PostgreSQL InfluxDB Docker Images

You can run `pg_influxdb` with [Docker images from DockerHub][1], for
example:

```bash
docker run -d \
  -e POSTGRES_PASSWORD=mysecret \
  -e INFLUXDB_DATABASE=metrics \
  -p 5432:5432 \
  -p 8086:8086 \
  -p 8089:8089/udp \
  mkindahl/pg_influxdb:latest
```

The container automatically configures `shared_preload_libraries`,
creates the target database, and installs the extension on first
start. Both the UDP and HTTP endpoints are configured and should work
out of the box.

## Environment Variables

To configure the Docker container, a number of environment variables
are available.

| Variable                     | Default        | Description                                   |
|------------------------------|----------------|-----------------------------------------------|
| `INFLUXDB_DATABASE`          | `postgres`     | Database for InfluxDB workers to connect to   |
| `INFLUXDB_HTTP_PORT`         | `8086`         | HTTP service port                             |
| `INFLUXDB_HTTP_WORKERS`      | `4`            | Number of HTTP worker processes               |
| `INFLUXDB_HTTP_AUTH`         | `off`          | Enable HTTP Basic Auth using PostgreSQL roles |
| `INFLUXDB_UDP_PORT`          | `8089`         | UDP service port                              |
| `INFLUXDB_UDP_WORKERS`       | `4`            | Number of UDP worker processes                |
| `INFLUXDB_UDP_SCHEMA`        | `measurements` | Schema for UDP writes                         |
| `INFLUXDB_AUTO_CREATE_TABLE` | `on`           | Auto-create tables for new measurements       |

All standard [PostgreSQL Docker environment variables][2] (e.g.,
`POSTGRES_PASSWORD`, `POSTGRES_USER`, `POSTGRES_DB`) are also
supported.

### Image Variants

Images are published for PostgreSQL 17 and 18 on four OS variants:
Debian Bookworm (`bookworm`), Debian Bullseye (`bullseye`), Debian
Trixie (`trixie`), and Alpine Linux (`alpine`). Note that Bullseye is
not available for PostgreSQL 18.

| OS                   | PostgreSQL 17             | PostgreSQL 18             |
|----------------------|---------------------------|---------------------------|
| Debian 11 "Bullseye" | `<version>-pg17-bullseye` |                           |
| Debian 12 "Bookworm" | `<version>-pg17-bookworm` | `<version>-pg18-bookworm` |
| Debian 13 "Trixie"   | `<version>-pg17-trixie`   | `<version>-pg18-trixie`   |
| Alpine               | `<version>-pg17-alpine`   | `<version>-pg18-alpine`   |

Image tag is `<version>-pg<version>-<os>`, for example
`1.0.0-pg17-alpine`.

Convenience tags are available:
- `latest` (PG 18, Debian Bookworm)
- `pg18` (PG18, Debian Bookworm)
- `pg17` (PG17, Debian Bookworm)

## Configuring HTTPS

The Docker image does not yet support TLS via environment variables. As a
workaround, supply the certificate files and a custom init script that
writes the SSL settings into `postgresql.conf`.

### Step 1: Prepare a certificate and key

For example, generate a self-signed certificate, or use an existing
CA-issued one:

```bash
openssl req -newkey rsa:2048 -nodes \
    -keyout server.key \
    -x509 -days 365 \
    -out server.crt \
    -subj "/CN=localhost"
chmod 600 server.key
```

### Step 2: Write a custom init script

Create your own init script for the container, for example
`initdb-tls.sh`:

```bash
#!/bin/bash
set -e
cat >> "$PGDATA/postgresql.conf" <<EOF
# TLS settings
ssl           = on
ssl_cert_file = 'server.crt'
ssl_key_file  = 'server.key'
influxdb.https = on
EOF
```

### Step 3: Mount the files and run the container

```bash
docker run -d \
  -e POSTGRES_PASSWORD=mysecret \
  -e INFLUXDB_DATABASE=metrics \
  -p 5432:5432 \
  -p 8086:8086 \
  -v "$(pwd)/server.crt:/var/lib/postgresql/data/server.crt" \
  -v "$(pwd)/server.key:/var/lib/postgresql/data/server.key" \
  -v "$(pwd)/initdb-tls.sh:/docker-entrypoint-initdb.d/initdb-tls.sh" \
  mkindahl/pg_influxdb:latest
```

The PostgreSQL Docker entrypoint runs all scripts in
`/docker-entrypoint-initdb.d/` in alphabetical order on first start, so
`initdb-tls.sh` runs after `initdb-pg-influxdb.sh` and appends the TLS
settings after the influxdb GUCs.

[1]: https://hub.docker.com/repository/docker/mkindahl/pg_influxdb/general
[2]: https://hub.docker.com/_/postgres

