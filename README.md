# InfluxDB API to PostgreSQL

This extension implements a InfluxDB API to PostgreSQL allowing you to
interact with PostgreSQL as if it was an InfluxDB instance.

Currently, it supports writing the InfluxDB Line Protocol to a
PostgreSQL database.

This is a re-implementation of the work done in [`pg_influx`][1] and
focused on providing a more complete API resembling InfluxDB API
version 1 and version 2 with both UDP and HTTP support. It also aims
to have better support for the InfluxDB Line Protocol and be a true
replacement for using InfluxDB to the extent that it is possible.

## Building and Installing

Install the [PGDG PostgreSQL version][pgdg]. For example

```bash
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get -y install postgresql postgresql-server-dev-13
```

To build and install the extension:

```
make && sudo make install
```

[pgdg]: https://wiki.postgresql.org/wiki/Apt

Add the database you want the workers to connect to in the
`postgresql.conf` file and add `influxdb` to
`shared_preload_libraries`:

```
shared_preload_libraries = `influxdb`
influxdb.database_name = 'my_database'
```

## InfluxDB Line Protocol

The [InfluxDB Line Protocol][ilp] is a compact line-oriented
protocol for sending measurements from devices.

The following example is from the [specification page][ilp]:

```
myMeasurement,tag1=value1,tag2=value2 fieldKey="fieldValue" 1556813561098000000
```

It consists of a measurement name, an optional set of tags, a set of
field values, and an optional timestamp, typically in nanoseconds
since the epoch.

[ilp]: https://docs.influxdata.com/influxdb/cloud/reference/syntax/line-protocol/

## Differences from InfluxDB Line Protocol

Compared to the [Influx Line Protocol Reference][2] there are some
subtle differences in semantics, which are outlined here.

### Quotes and backslashes

From section [Duplicate points][duplicate] we have the following text:

> A point is uniquely identified by the measurement name, tag set, and
> timestamp. If you submit line protocol with the same measurement,
> tag set, and timestamp, but with a different field set, the field
> set becomes the union of the old field set and the new field set,
> where any conflicts favor the new field set.

And from the [section on quotes][quotes] we have:

> Line protocol accepts double and single quotes in measurement names,
> tag keys, tag values, and field keys, but interprets them as part of
> the name, key, or value.

This means that keys `"more magic"` and `more\ magic` are considered
different when compared.

For `pg_influxdb` quotes and backslashes are not considered part of
the string or symbol. This means that `"more magic"`, `more\ magic`,
and `'more magic'` are considered equal as strings and as a result the
following lines are considered duplicates according to the definition
above.

```
my\ Measurement,"tag key1"="device" fieldKey=100 1556813561098000000
"my Measurement",tag\ key1=device fieldKey=100 1556813561098000000
'my Measurement','tag key1'=device fieldKey=100 1556813561098000000
```

To disable this behavior and include the quotes in the string, set
the GUC `influxdb.keep_quotes` to `on`.

### Boolean values

From [section on boolean values][boolean] only the values `t`, `T`,
`true`, `True`, `TRUE`, `f`, `F`, `false`, `False`, and `FALSE` are
boolean. According to this definition, it means that `tRue` is not a
boolean, but with `pg_influxdb` we consider values `T`, `TRUE`, `F`,
and `FALSE` in all combinations of case as boolean. This means that
also `tRue` is a boolean (if not quoted).

[1]: https://github.com/timescale/pg_influx
[2]: https://docs.influxdata.com/influxdb/cloud/reference/syntax/line-protocol
[quotes]: https://docs.influxdata.com/influxdb/cloud/reference/syntax/line-protocol/#quotes
[boolean]: https://docs.influxdata.com/influxdb/cloud/reference/syntax/line-protocol/#boolean
[duplicate]: https://docs.influxdata.com/influxdb/v2/reference/syntax/line-protocol/#duplicate-points

## HTTP Endpoint

Here is an example that can be used to feed data to the HTTP
endpoint. Notice that you cannot select the database to write to since
the worker has to connect to a database before starting and then has
to keep connected to that database.

```bash
curl -i -XPOST 'http://localhost:8086/write \
    --data-binary 'cpu_load_short,host=server01,region=us-west value=0.64 1434055562000000000'`
```

## Options

The following options are available:

`influxdb.keep_quotes` (`boolean`)
: Keep quotes for a string as part of the actual string. Quotes are normally
: not part of the string, as outlined above, but if you want to keep
: the quotes, then set this to `on`. Default is `off`. This option can
: be set at any time and not only in the configuration file.

`influxdb.auto_create_table` (`boolean`)
: Auto-create a default table if no table exists for the measurement
: that arrived. This allows users to first collect measurements and
: then later decide what measurements are interesting and how the
: table definitions should look. Default is `off`. This option can
: be set at any time and not only in the configuration file.

`influxdb.http_workers` (`integer`)
: The number of HTTP workers to spawn when starting the
: server. Default is to spawn 4 workers.

`influxdb.http_service` (`string`)
: Service name or port number to use for the HTTP service. If you use
: a string here, it will be looked up using `getservbyname` so you can
: use something like `http` if you want. Default is to use the same
: port as InfluxDB, which is 8086.

`influxdb.database_name` (`string`)
: Name of the database that the HTTP workers shall connect to.

`influxdb.schema_name` (`string`)
: Name of the schema where all measurement tables are stored. Default
: is `measurements`.

## Functions

There are some functions available, which are mostly for debugging and
testing:

`FUNCTION influxdb.parse_text(text) RETURNS SETOF jsonb`
: Parse an InfluxDB text block into multiple lines and return the
: parsed result as JSONB. This is mostly intended to test the parser.

`FUNCTION influxdb.tokenize(text) RETURNS TABLE(kind integer, value text)`
: Process a text consisting of InfluxDB protocol lines and return the
: tokens. Intended for testing the tokenizer.

`PROCEDURE process_text(regnamespace, text)`
: Procedure for processing a set of InfluxDB protocol lines and insert
: them into the correct table.

## Copyrights

For the `http_parser.c` and `http_parser.h` files, the following MIT
license applies:

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
