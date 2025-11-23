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

drop schema testing cascade;
drop extension influxdb;
