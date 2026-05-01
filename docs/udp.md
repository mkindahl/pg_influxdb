# PostgreSQL InfluxDB Extension UDP Endpoint

The UDP endpoint accepts [InfluxDB Line Protocol][line-protocol] datagrams
and writes them to PostgreSQL tables. It is disabled by default.

## Enabling the UDP endpoint

TO enable the UDP endpoint, set `influxdb.udp_workers` to the number
of workers to use in `postgresql.conf` and restart PostgreSQL. FOr
example, to configure PostgreSQL to start 4 UDP workers:

```
influxdb.udp_workers = 4
```

Each worker listens on the UDP socket using `SO_REUSEPORT`, so the
kernel distributes incoming datagrams across all workers.

## Configuration

| Parameter                  | Default        | Description                                                    |
|----------------------------|----------------|----------------------------------------------------------------|
| `influxdb.udp_workers`     | `0`            | Number of UDP worker processes to spawn                        |
| `influxdb.udp_service`     | `8089`         | Port number or service name to listen on                       |
| `influxdb.udp_schema`      | `measurements` | PostgreSQL schema that receives all UDP writes                 |
| `influxdb.udp_read_buffer` | `0`            | Socket receive buffer size in kB (`SO_RCVBUF`); 0 = OS default |

All four parameters require a server restart to take effect.

Because UDP carries no query parameters, `influxdb.udp_schema` is the only
way to direct writes to a particular schema. All measurements received over
UDP are written to tables in that schema.

## Sending data

Send line protocol text as a UDP datagram. A single datagram may contain
multiple newline-separated lines:

```bash
printf 'cpu,host=server01 usage_idle=95.91 1574753954000000000\n' \
    | nc -u -q1 localhost 8089
```

Or using `socat`:

```bash
echo 'cpu,host=server01 usage_idle=95.91 1574753954000000000' \
    | socat - UDP:localhost:8089
```

The measurement name maps directly to the table name within
`influxdb.udp_schema`. The example above writes to `measurements.cpu`.

> [!NOTE]
> UDP is a fire-and-forget protocol. There is no acknowledgment or error
> response. If a datagram contains malformed line protocol, the error is
> logged server-side and the datagram is discarded; valid subsequent
> datagrams continue to be processed normally.

## Limits

- **Maximum datagram size**: 64 KB. Datagrams larger than this are silently
  truncated by the OS before reaching the worker.
- **Socket receive buffer**: controlled by `influxdb.udp_read_buffer`. The
  OS default is usually between 256 KB and 4 MB. Increase this if you
  observe dropped datagrams at high ingest rates.

[line-protocol]: https://docs.influxdata.com/influxdb/cloud/reference/syntax/line-protocol
