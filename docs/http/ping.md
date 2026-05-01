# PostgreSQL InfluxDB Extension HTTP `/ping` endpoint

The `/ping` endpoint is a health check that confirms the server is
running.  It returns no body and is always available, even when
`influxdb.http_auth` is enabled.

### Requests

The server accepts any HTTP method. A `GET` request is conventional:

```bash
curl -is http://localhost:8086/ping
```

### Responses

A successful response has status `204 No Content` with no body and an
`X-Influxdb-Version` header identifying the server:

```
HTTP/1.1 204 No Content
X-Influxdb-Version: pg_influxdb
```
