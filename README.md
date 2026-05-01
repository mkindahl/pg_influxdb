# PgInfluxDB: InfluxDB API to PostgreSQL

This extension implements a [InfluxDB API][influx-api] to PostgreSQL
allowing you to interact with PostgreSQL as if it was an InfluxDB
instance.

Currently, it supports writing the InfluxDB Line Protocol to a
PostgreSQL database.

This is a re-implementation of the work done in [`pg_influx`][1]
focused on providing a more complete API resembling [InfluxDB API][2]
version 1 and version 2 (although only version 1 is supported
currently) with both UDP and HTTP support .

It also aims to have better support for the InfluxDB Line Protocol and
be a true replacement for using InfluxDB in a limited set of
scenarios, in particular supporting [Telegraf][3] endpoints speaking
the [InfluxDB Line Protocol][4].

## Documentation

- [InfluxDB Line Protocol](docs/line_protocol.md)
- [PostgreSQL InfluxDB Extension HTTP Endpoint](docs/http/index.md)
- [PostgreSQL InfluxDB Extension UDP Endpoint](docs/udp.md)
- [PostgreSQL InfluxDB Extension Docker Image](docs/docker.md)
- [PostgreSQL InfluxDB Extension Options](docs/options.md)
- [PostgreSQL InfluxDB Extension Functions](docs/functions.md)

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

To build and install the extension you need to have an installation of
the PostgreSQL server with development libraries.

### Building and installing the PostgreSQL server

The package requires PostgreSQL version 17 or later, so you need to
install the [PGDG PostgreSQL version][pgdg]. For example:

```bash
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get install postgresql-18 postgresql-server-dev-18
```

### Building and installing the extension

Once you have installed a suitable PostgreSQL server, you can build
and install the extension:

```
make && sudo make install
```

SSL support is enabled by default when PostgreSQL was built with OpenSSL (the
standard case for packages from [PGDG][pgdg]). To build without SSL support:

```
make USE_SSL=0 && sudo make USE_SSL=0 install
```

[1]: https://github.com/timescale/pg_influx
[2]: https://docs.influxdata.com/influxdb/v1/tools/api
[3]: https://github.com/influxdata/telegraf
[4]: https://docs.influxdata.com/influxdb/cloud/reference/syntax/line-protocol
[pgdg]: https://wiki.postgresql.org/wiki/Apt

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

    Copyright (C) 2025 Mats Kindahl

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
