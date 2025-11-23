create extension influxdb;
create schema testing;

show influxdb.auto_create_table;

\set ON_ERROR_STOP 0
call influxdb.process_line('testing', E'disk free=527806464i,total=0i 1574753954000000000');
\set ON_ERROR_STOP 1

set influxdb.auto_create_table to on;

call influxdb.process_line('testing', E'disk free=527806464i,total=0i 1574753954000000000');

\d testing.*
\x on
select * from testing.disk;
\x off

-- Modify the table and add a new column for the "free" field.
alter table testing.disk add column free integer;

\d testing.*

-- This will move the fields that was just added into the new field.
update testing.disk
set free = (_fields->>'free')::integer,
    _fields = _fields - 'free';

-- Test processing a new line and make sure that a new plan is
-- constructed for the insert statement.
\x on
select * from testing.disk;
call influxdb.process_line('testing', E'disk free=12345678i,total=0i 1574753955000000000');
select * from testing.disk;
\x off

drop schema testing cascade;
drop extension influxdb;
