# PostgreSQL InfluxDB Extension HTTP Authentication

The HTTP endpoint supports Basic Authentication backed by PostgreSQL roles.
When enabled, every request except `/ping` must supply valid credentials.

## Enabling authentication

Set `influxdb.http_auth = on` in `postgresql.conf` and restart PostgreSQL:

```
influxdb.http_auth = on
```

Credentials are verified against PostgreSQL roles, so the role must exist
and have a password set:

```sql
CREATE USER telegraf WITH PASSWORD 'secret';
```

Both MD5 and SCRAM-SHA-256 password hashes are supported.

> [!NOTE]
> When `influxdb.http_auth` is enabled without TLS, credentials are sent in
> cleartext. Enable `influxdb.https` or use a TLS-terminating reverse proxy
> to protect credentials in transit.

## Supplying credentials

Credentials can be provided in two ways.

### Authorization header

Send a standard `Authorization: Basic` header with the credentials
base64-encoded as `username:password`:

```bash
curl -u telegraf:secret 'http://localhost:8086/write?db=metrics' \
    --data-binary 'cpu,host=server01 usage_idle=95.91'
```

### Query parameters

Pass `u=` and `p=` as URL query parameters:

```bash
curl 'http://localhost:8086/write?db=metrics&u=telegraf&p=secret' \
    --data-binary 'cpu,host=server01 usage_idle=95.91'
```

If both are present, the query parameters take precedence over the
`Authorization` header.

## Failed authentication

A request with missing or invalid credentials receives a `401 Unauthorized`
response:

```
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Basic realm="InfluxDB"
Content-Type: application/json

{"error":"authorization failed"}
```
