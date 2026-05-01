# PostgreSQL InfluxDB Extension HTTP Endpoint

The HTTP endpoint is mimicing the [InfluxDB API][influx-api].

## Endpoints

- [Ingesting data using the HTTP `/write` endpoint](write.md)
- [Health checks using the HTTP `/ping` endpoint](ping.md)
- [Issuing queries using the HTTP `/query` endpoint](query.md)
- [Basic HTTP Authentication Configuration and Usage](auth.md)
- [HTTPS/TLS Configuration and Usage](https.md)

## Configuration

| Parameter                           | Default | Description                                                     |
|-------------------------------------|---------|-----------------------------------------------------------------|
| `influxdb.http_workers`             | `4`     | Number of HTTP worker processes to spawn                        |
| `influxdb.http_service`             | `8086`  | Port number or service name to listen on                        |
| `influxdb.database`                 |         | PostgreSQL database that workers connect to                     |
| `influxdb.http_auth`                | `off`   | Enable Basic Authentication using PostgreSQL roles              |
| `influxdb.https`                    | `off`   | Enable TLS on the HTTP listener                                 |
| `influxdb.https_service`            |         | Port for a dedicated HTTPS listener alongside the HTTP listener |
| `influxdb.http_worker_restart_time` | `20`    | Seconds to wait before restarting a failed worker; `0` = never  |

All parameters except `influxdb.http_workers` require a server restart
to take effect. The parameter `influxdb.http_workers` can be changed
with a configuration reload.

[influx-api]: https://docs.influxdata.com/influxdb/v1/tools/api
