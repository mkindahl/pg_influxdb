-- InfluxDB API to PostgreSQL. Copyright (C) 2025 Mats Kindahl
--    
-- This program is free software: you can redistribute it and/or
-- modify it under the terms of the GNU Affero General Public License
-- as published by the Free Software Foundation, either version 3 of
-- the License, or (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful, but
-- WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
-- Affero General Public License for more details.
--    
-- You should have received a copy of the GNU Affero General Public
-- License along with this program.  If not, see
-- <https://www.gnu.org/licenses/>.

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
