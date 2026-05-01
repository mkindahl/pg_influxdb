# PostgreSQL InfluxDB Extension Options

## General Options

`influxdb.database` (`string`)
: Name of the database that all workers connect to. Must be set before
  starting the server. Changes to this variable requires a server restart to
  take effect.

`influxdb.keep_quotes` (`boolean`)
: Keep quotes for a string as part of the actual string. Quotes are
  normally not part of the string, as outlined above, but if you want
  to keep the quotes, then set this to `on`. Default is `off`. Can be
  changed at any time.

`influxdb.auto_create_table` (`boolean`)
: Auto-create a default table if no table exists for the measurement
  that arrived. This allows users to first collect measurements and
  then later decide what measurements are interesting and how the
  table definitions should look. Default is `off`. Can be changed at
  any time.

## HTTP Options

`influxdb.http_workers` (`integer`)
: The number of HTTP workers to spawn. Default is `4`. Set to `0` to
  disable the HTTP endpoint. Requires a configuration reload to take
  effect.

`influxdb.http_service` (`string`)
: Service name or port number to listen on for HTTP connections. If a
  service name is given, it is looked up using `getservbyname`. Default
  is `8086`. Changes to this variable requires a server restart to
  take effect.

`influxdb.http_worker_restart_time` (`integer`)
: Seconds to wait before restarting a failed HTTP worker. Set to `0`
  to never restart. Default is `20`. Changes to this variable requires
  a server restart to take effect.

## Authentication Options

`influxdb.http_auth` (`boolean`)
: Enable HTTP Basic Authentication using PostgreSQL roles. When
  enabled, HTTP requests must provide credentials matching a
  PostgreSQL role created with `CREATE USER ... WITH PASSWORD`.
  Credentials can be provided via the `Authorization: Basic` header
  or `u=` and `p=` query parameters. The `/ping` endpoint is exempt
  from authentication. Default is `off`. Changes to this variable requires a server restart to
  take effect.

> [!NOTE]
> When `influxdb.http_auth` is enabled without `influxdb.https` or
> `influxdb.https_service`, credentials are sent in cleartext. Enable
> one of the TLS options, or use a TLS-terminating reverse proxy, to
> protect credentials in transit.

## HTTPS/TLS Options

`influxdb.https` (`boolean`)
: Enable TLS on the HTTP listener (`influxdb.http_service`). When
  `on`, the listener uses the certificate and key from PostgreSQL's
  `ssl_cert_file` and `ssl_key_file` GUC parameters. If `ssl_ca_file`
  is also set, mutual TLS (client certificate authentication) is
  enabled. TLS 1.2 is the minimum accepted version. Default is `off`.

  If enabled, the port being used is by default taken from
  `influxdb.http_service`. This makes it easy to just enable HTTPS by
  setting `influxdb.https = on`. If you want to serve both HTTP and
  HTTPS at the same time, use `influxdb.https_service`. Changes to
  this variable requires a server restart to take effect.

`influxdb.https_service` (`string`)
: Service name or port number for a **dedicated HTTPS listener** that
  runs alongside the existing HTTP listener. When set to a non-empty
  value, an additional set of workers (equal in count to
  `influxdb.http_workers`) starts on this port with TLS always
  enabled. Certificate configuration is the same as for
  `influxdb.https`: the `ssl_cert_file`, `ssl_key_file`, and
  `ssl_ca_file` GUC parameters are used. Default is empty (disabled).

  This parameter allows HTTP and HTTPS clients to be served
  simultaneously on separate ports. For example:

  ```
  influxdb.http_service  = '8086'   # plain HTTP
  influxdb.https_service = '8443'   # TLS on a second port
  ```

  Changes to this variable requires a server restart to
  take effect.

## UDP

`influxdb.udp_workers` (`integer`)
: Number of UDP worker processes to spawn. Set to `0` (the default) to
  disable the UDP endpoint. Each worker gets its own socket using
  `SO_REUSEPORT` so the kernel distributes incoming datagrams across
  all workers. Changes to this variable requires a server restart to
  take effect.

`influxdb.udp_service` (`string`)
: Service name or port number to listen on for UDP datagrams. Default
  is `8089`. Changes to this variable requires a server restart to
  take effect.

`influxdb.udp_schema` (`string`)
: PostgreSQL schema that receives all UDP writes. Because UDP carries
  no query parameters, this is the only way to direct UDP writes to a
  particular schema. Default is `measurements`. Changes to this
  variable requires a server restart to take effect.

`influxdb.udp_read_buffer` (`integer`)
: Socket receive buffer size in kB (`SO_RCVBUF`). Set to `0` to use
  the OS default, which is typically between 256 kB and 4 MB. Increase
  this if you observe dropped datagrams at high ingest rates. Default
  is `0`. Changes to this variable requires a server restart to take
  effect.
