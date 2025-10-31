# InfluxDB API to PostgreSQL

This extension implements a InfluxDB API to PostgreSQL allowing you to
interact with PostgreSQL as if it was an InfluxDB instance.

Currently, it supports writing the InfluxDB Line Protocol to a
PostgreSQL database.

This is a re-implementation of the work done in [`pg_influx`][1] and
focused on providing a more complete API resembling InfluxDB API
version 1 and version 2 with both UDP and HTTP support. It also aims
to have better support for the InfluxDB Line Protocol and be a true
replacement for using InfluxDB.

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

To disable this behaviour and include the quotes in the string, set
the GUC `influxdb.keep_quotes` to `on`.

### Boolean values

From [section on boolean values][boolean] only the values `t`, `T`,
`true`, `True`, `TRUE`, `f`, `F`, `false`, `False`, and `FALSE` are
booleans. According to this definition, it means that `tRue` is not a
boolean, but with `pg_influxdb` we consider values `T`, `TRUE`, `F`,
and `FALSE` in all combinations of case as booleans. This means that
also `tRue` is a boolean (if not quoted).

[1]: https://github.com/timescale/pg_influx
[2]: https://docs.influxdata.com/influxdb/cloud/reference/syntax/line-protocol
[quotes]: https://docs.influxdata.com/influxdb/cloud/reference/syntax/line-protocol/#quotes
[boolean]: https://docs.influxdata.com/influxdb/cloud/reference/syntax/line-protocol/#boolean
[duplicate]: https://docs.influxdata.com/influxdb/v2/reference/syntax/line-protocol/#duplicate-points
