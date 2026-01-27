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

[influx-api]: https://docs.influxdata.com/influxdb/v1/tools/api
[line-protocol]: https://docs.influxdata.com/influxdb/cloud/reference/syntax/line-protocol
