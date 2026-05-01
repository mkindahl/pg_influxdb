# PostgreSQL InfluxDB Extension HTTP `/query` endpoint

The `/query` endpoint implements a small subset of the [InfluxDB query
API][influx-api] sufficient for clients such as [Telegraf][telegraf]
that send a `CREATE DATABASE` statement before writing data. It is
minimal at this point and only support `CREATE DATABASE`, but has the
infrastructure to support more commands if necessary.

### Requests

The query endpoint accepts `POST` requests with an
`application/x-www-form-urlencoded` body containing a `q=` parameter:

```bash
curl -is http://localhost:8086/query --data-urlencode 'q=CREATE DATABASE metrics'
```

#### CREATE DATABASE

`CREATE DATABASE <name>` creates the PostgreSQL schema `<name>` if it
does not already exist. It is equivalent to `CREATE SCHEMA IF NOT
EXISTS <name>`.

### Responses

A successful response has status `200 OK` with a JSON body:

```json
{"results":[{}]}
```

On error, the response has status `400 Bad Request`:

```json
{"results":[{"error":"<message>"}]}
```

Where `<message>` is either `syntax error` for unparseable input or
`unrecognized query` for any statement other than `CREATE DATABASE`.

[influx-api]: https://docs.influxdata.com/influxdb/v1/tools/api
[telegraf]: https://github.com/influxdata/telegraf
