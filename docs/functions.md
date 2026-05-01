# PostgreSQL InfluxDB Extension Functions

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

