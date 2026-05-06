# InfluxDB Line Protocol

The [InfluxDB Line Protocol][line-protocol] is a compact line-oriented
protocol for sending measurements from devices.

The following example is from the [specification page][line-protocol]:

```
myMeasurement,tag1=value1,tag2=value2 fieldKey="fieldValue" 1556813561098000000
```

It consists of a measurement name, an optional set of tags, a set of
field values, and an optional timestamp, typically in nanoseconds
since the epoch.

## Differences from InfluxDB Line Protocol

Compared to the [Influx Line Protocol Reference][line-protocol] there
are some subtle differences in semantics, which are outlined here.

### Quotes and backslashes

Section [Duplicate points][duplicate] contains:

> A point is uniquely identified by the measurement name, tag set, and
> timestamp. If you submit line protocol with the same measurement,
> tag set, and timestamp, but with a different field set, the field
> set becomes the union of the old field set and the new field set,
> where any conflicts favor the new field set.

And [section on quotes][quotes] contains:

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
boolean, but with `pg_influxdb` values `T`, `TRUE`, `F`, and `FALSE`
in all combinations of case are considered boolean. This means that
also `tRue` is a boolean (if not quoted).

### Escape sequences in string field values

The InfluxDB line protocol defines exactly two escape sequences for
double-quoted string field values:

| Sequence | Meaning                    |
|----------|----------------------------|
| `\"`     | Literal double quote (`"`) |
| `\\`     | Literal backslash (`\`)    |

Other backslash sequences are **not** an escape sequence. The
backslash and the following character are both stored as they are. For
example, `"hello\nworld"` is stored as the twelve characters
`hello\nworld`, not as a newline. This matches the behaviour of the
reference implementation (`unescapeStringField` in
[`models/points.go`][points-go]).

Symbols (measurement names, tag keys, tag values, field keys) use a
different convention: a backslash escapes a comma (`\,`), an equals
sign (`\=`), or a space (`\ `). The backslash is stripped and the
following character is kept.

### Line endings

According to the [Influx Line Protocol Reference][line-protocol] a
timestamp can be missing, but if there is a blank at the end of the
line, this would generate a syntax error. This is very difficult to
spot so instead blanks are allowed at the end of the line even when
there is no timestamp.

[boolean]: https://docs.influxdata.com/influxdb/cloud/reference/syntax/line-protocol/#boolean
[duplicate]: https://docs.influxdata.com/influxdb/v2/reference/syntax/line-protocol/#duplicate-points
[line-protocol]: https://docs.influxdata.com/influxdb/cloud/reference/syntax/line-protocol
[points-go]: https://github.com/influxdata/influxdb/blob/1.11/models/points.go#L1314
[quotes]: https://docs.influxdata.com/influxdb/cloud/reference/syntax/line-protocol/#quotes
