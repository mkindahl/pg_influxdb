# HTTP Endpoint

The HTTP endpoint is mimicing the [InfluxDB API][influx-api], but
right now only handles writes.

## HTTP `/write` endpoint

The `/write` endpoint is used to write rows to the database and it
requires a `db` parameter to be provided with the URL signifying the
schema that will be used for the metric table.

> [!NOTE]
> After processing a single request, the connection is immediately
> shut down with a `Connection: close` header, regardless of what the
> client requested. This is allowed by the HTTP standard, but it might
> come as a suprise to the user.

### Requests

The server accept `POST` requests with lines in the [InfluxDB Line
Protocol][line-protocol] format as input. The rows are written to a table with
the same name as the measurement and in the schema given by the `db`
parameter.

For example, to write a few metrics to the table `metrics.cpu` table,
you can use the following `curl` command:

```bash
curl -is 'http://localhost:8086/write?db=metrics' --data-binary @- <<END_OF_INPUT
cpu,cpu=cpu0,host=fury usage_guest=0,usage_idle=95.91 1574753954000000000
cpu,cpu=cpu1,host=fury usage_guest=0,usage_idle=92.15 1574753954000000000
cpu,cpu=cpu2,host=fury usage_guest=0,usage_idle=90.74 1574753954000000000
END_OF_INPUT
```

For the requests, the `Content-Type` is currently ignored, but for
future compatibility you should use a `Content-Type` header with
`application/x-www-form-urlencoded`, `application/octet-stream` (which
is the HTTP default is no content type is provided), or `text/plain`.

> [!NOTE]
> The content type `application/x-www-form-urlencoded` is supported
> since the examples on the [InfluxDB API][influx-api] uses this with
> the examples so it is likely to be supported also in the future.

### Responses

For any responses that contains contents, the responses sent back are
always using content type `application/json` with the content being a
JSON object with the following fields:

`error`
: Brief error message. This is the same as provided by InfluxDB.

`detail`
: Error message details, if available. This is not available from
  InfluxDB.

## Configuring HTTPS

`pg_influxdb` reuses PostgreSQL's own TLS certificate files, so if
PostgreSQL is already configured for SSL, enabling HTTPS for the
InfluxDB listener requires only one additional line in
`postgresql.conf` that sets `influxdb.https`.

### Prerequisites

PostgreSQL must be compiled with SSL support (the default for packages
from [PGDG][pgdg]) and a certificate and private key must be
present. The relevant PostgreSQL GUC parameters are:

| Parameter       | Default      | Description                              |
|-----------------|--------------|------------------------------------------|
| `ssl_cert_file` | `server.crt` | PEM-encoded server certificate (chain)   |
| `ssl_key_file`  | `server.key` | PEM-encoded private key                  |
| `ssl_ca_file`   |              | CA certificate for client authentication |

Relative paths are resolved against the PostgreSQL data directory
(`$PGDATA`). Absolute paths may also be used.

### Quick start with a self-signed certificate

To generate a self-signed certificate valid for 365 days:

```bash
openssl req -newkey rsa:2048 -nodes \
    -keyout "$PGDATA/server.key" \
    -x509 -days 365 \
    -out "$PGDATA/server.crt" \
    -subj "/CN=localhost"

chmod 600 "$PGDATA/server.key"
```

Note that you need to set the mode of the [key file to only be readable by the
file owner, or alternatively be owned by root and have group read permissions by
the postgres owner][libpq-ssl]. Otherwise it will not be used and an error will
be generated that the file is missing.

You can then add the certificate and key file in `postgresql.conf` and enable
HTTPS:

```
ssl            = on
ssl_cert_file  = 'server.crt'   # relative to $PGDATA (these are the defaults)
ssl_key_file   = 'server.key'

influxdb.https = on
```

After that you can restart PostgreSQL using `pg_ctl restart` and verify that the
certificate works by sending a ping command to the server:

```bash
curl --cacert "$PGDATA/server.crt" https://localhost:8086/ping -v
# Expect: HTTP/1.1 204 No Content
```

### Using an existing CA-issued certificate

Place (or symlink) your certificate and key in `$PGDATA`, or set
`ssl_cert_file` and `ssl_key_file` to absolute paths, then enable
`influxdb.https` as above.

### Mutual TLS (client certificate authentication)

To require clients to present a certificate signed by a trusted CA,
set `ssl_ca_file` to the CA certificate and enable both HTTPS and
auth:

```
ssl_ca_file    = 'root.crt'
influxdb.https = on
influxdb.http_auth = on
```

Clients must then pass their certificate and key when connecting,
for example:

```bash
curl https://localhost:8086/ping \
    --cacert root.crt \
    --cert client.crt \
    --key client.key
```

### Serving HTTP and HTTPS simultaneously

Normally, HTTP or HTTPS are served through the 8086 port (or whatever
the value of `influxdb.http_service` is) and enabling HTTPS will just
result in 8086 used for HTTPS traffic.

If you, however, want to serve both HTTP and HTTPS traffic on the same
server, this is possible by setting `influxdb.https_service` to a
second port to run a TLS listener alongside the existing plain-HTTP
listener:

```
influxdb.http_service  = '8086'    # plain HTTP (existing clients)
influxdb.https_service = '8443'    # TLS (new or security-conscious clients)
```

Both listeners share the same `influxdb.http_workers` pool size. To
disable the plain-HTTP listener entirely, set
`influxdb.http_workers = 0` and put all traffic on the HTTPS port:

```
influxdb.http_workers  = 0
influxdb.https_service = '8086'
```

> [!NOTE]
> When `influxdb.https_service` is not set, the port number is read,
> somewhat unintuitively, from `influxdb.http_service`. This is so
> that it should be easy to enable HTTPS by just setting
> `influxdb.https = on`. You should only use `influxdb.https_service`
> if you want to serve both HTTP and HTTPS traffic from the same
> server.

### Verifying the TLS configuration

Check that the listener rejects older protocol versions:

```bash
openssl s_client -connect localhost:8086 -tls1_1   # should fail
openssl s_client -connect localhost:8086 -tls1_2   # should succeed
```

[libpq-ssl]: https://www.postgresql.org/docs/current/libpq-ssl.html#LIBPQ-SSL-CLIENTCERT
[influx-api]: https://docs.influxdata.com/influxdb/v1/tools/api
[line-protocol]: https://docs.influxdata.com/influxdb/cloud/reference/syntax/line-protocol

