# InfluxDB API to PostgreSQL

This extension implements a [InfluxDB API][influx-api] to PostgreSQL
allowing you to interact with PostgreSQL as if it was an InfluxDB
instance.

Currently, it supports writing the InfluxDB Line Protocol to a
PostgreSQL database.

This is a re-implementation of the work done in
[`pg_influx`][pg-influx] and focused on providing a more complete API
resembling [InfluxDB API][influx-api] version 1 and version 2 with
both UDP and HTTP support (although only version 1 is supported
currently).

It also aims to have better support for the InfluxDB Line Protocol and
be a true replacement for using InfluxDB to the extent that it is
possible.

- [InfluxDB Line Protocol](docs/line_protocol.md)
- [InfluxDB HTTP Endpoint](docs/http_endpoint.md)
- [InfluxDB Docker Image](docs/docker.md)

## Dependencies


**Runtime dependencies**:

- PostgreSQL 17 or 18
- zlib

**Build-time dependencies**:

- PostgreSQL server development headers (`postgresql-server-dev-17`
  or `postgresql-server-dev-18`)
- zlib development headers (`zlib1g-dev`)
- A C compiler (gcc or clang)

**Testing dependencies**:

- Perl modules `IPC::Run`, `HTTP::Response`, and `JSON`.

On Debian/Ubuntu, install all build and test dependencies with:

```bash
sudo apt-get install postgresql-server-dev-18 zlib1g-dev \
    libipc-run-perl libhttp-message-perl libjson-perl
```

## Building and Installing

Install the [PGDG PostgreSQL version][pgdg]. For example

```bash
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get -y install postgresql-18 postgresql-server-dev-18
```

To build and install the extension:

```
make && sudo make install
```

[pgdg]: https://wiki.postgresql.org/wiki/Apt

## Options

The following options are available:

`influxdb.keep_quotes` (`boolean`)
: Keep quotes for a string as part of the actual string. Quotes are
  normally not part of the string, as outlined above, but if you want
  to keep the quotes, then set this to `on`. Default is `off`. This
  option can be set at any time and not only in the configuration
  file.

`influxdb.auto_create_table` (`boolean`)
: Auto-create a default table if no table exists for the measurement
  that arrived. This allows users to first collect measurements and
  then later decide what measurements are interesting and how the
  table definitions should look. Default is `off`. This option can be
  set at any time and not only in the configuration file.

`influxdb.http_workers` (`integer`)
: The number of HTTP workers to spawn when starting the
  server. Default is to spawn 4 workers.

`influxdb.http_service` (`string`)
: Service name or port number to use for the HTTP service. If you use
  a string here, it will be looked up using `getservbyname` so you can
  use something like `http` if you want. Default is to use the same
  port as InfluxDB, which is 8086.

`influxdb.database` (`string`)
: Name of the database that the HTTP workers shall connect to.

`influxdb.http_auth` (`boolean`)
: Enable HTTP Basic Authentication using PostgreSQL roles. When
  enabled, HTTP requests must provide credentials matching a
  PostgreSQL role created with `CREATE USER ... WITH PASSWORD`.
  Credentials can be provided via the `Authorization: Basic` header
  or `u=` and `p=` query parameters. The `/ping` endpoint is exempt
  from authentication. Default is `off`.

> [!WARNING]
> The extension does not support TLS. Credentials are sent in
> cleartext over the wire (Base64-encoded in the `Authorization`
> header or as query parameters). If you enable authentication, use
> a TLS-terminating reverse proxy (e.g., nginx, HAProxy, or stunnel)
> in front of the endpoint to protect credentials in transit.

## Functions

There are some functions available, which are mostly for debugging and
testing:

`FUNCTION influxdb.parse_text(text) RETURNS SETOF jsonb`
: Parse an InfluxDB text block into multiple lines and return the
  parsed result as JSONB. This is mostly intended to test the parser.

`FUNCTION influxdb.tokenize(text) RETURNS TABLE(kind integer, value text)`
: Process a text consisting of InfluxDB protocol lines and return the
  tokens. Intended for testing the tokenizer.

`PROCEDURE process_text(regnamespace, text)`
: Procedure for processing a set of InfluxDB protocol lines and insert
  them into the correct table.

## Copyrights

For the `src/http/http_parser.c` and `src/http/http_parser.h` files,
the following MIT license applies:

    Copyright Joyent, Inc. and other Node contributors.

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to
    deal in the Software without restriction, including without limitation the
    rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
    sell copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
    IN THE SOFTWARE. 

For all other files, the GNU Affero General Public License applies:

    InfluxDB API to PostgreSQL. Copyright (C) 2025 Mats Kindahl

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as
    published by the Free Software Foundation, either version 3 of the
    License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public
    License along with this program.  If not, see
    <https://www.gnu.org/licenses/>.

[pg-influx]: https://github.com/timescale/pg_influx
[line-protocol]: https://docs.influxdata.com/influxdb/cloud/reference/syntax/line-protocol
[influx-api]: https://docs.influxdata.com/influxdb/v1/tools/api




