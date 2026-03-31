# PostgreSQL InfluxDB Docker Images

You can run `pg_influxdb` with [Docker images from
DockerHub][dockerhub], for example:

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

[dockerhub]: https://hub.docker.com/repository/docker/mkindahl/pg_influxdb/general

## Environment Variables

| Variable                     | Default        | Description                                   |
|------------------------------|----------------|-----------------------------------------------|
| `INFLUXDB_DATABASE`          | `postgres`     | Database for influxdb workers to connect to   |
| `INFLUXDB_HTTP_PORT`         | `8086`         | HTTP service port                             |
| `INFLUXDB_HTTP_WORKERS`      | `4`            | Number of HTTP worker processes               |
| `INFLUXDB_HTTP_AUTH`         | `off`          | Enable HTTP Basic Auth using PostgreSQL roles |
| `INFLUXDB_UDP_PORT`          | `8089`         | UDP service port                              |
| `INFLUXDB_UDP_WORKERS`       | `4`            | Number of UDP worker processes                |
| `INFLUXDB_UDP_SCHEMA`        | `measurements` | Schema for UDP writes                         |
| `INFLUXDB_AUTO_CREATE_TABLE` | `on`           | Auto-create tables for new measurements       |

All standard [PostgreSQL Docker environment variables][pg-docker] (e.g.,
`POSTGRES_PASSWORD`, `POSTGRES_USER`, `POSTGRES_DB`) are also supported.

[pg-docker]: https://hub.docker.com/_/postgres

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

