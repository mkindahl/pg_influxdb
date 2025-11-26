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

create table testing.disk(_time timestamptz, _tags jsonb, _fields jsonb);

CALL influxdb.process_line('testing', E'disk,mode=rw,path=/boot/efi free=527806464i,inodes_free=i,total=0i,used_percent=1.4929822952022749 1574753954000000000');
CALL influxdb.process_line('testing', E'disk,mode=0 free=527806464i,total=0i 1574753954000000000');
CALL influxdb.process_line('testing', E'disk free=527806464i,total=0i 1574753954000000000');
CALL influxdb.process_line('testing', E'disk,mode=0,path=0i free=527806464i,total=0i 1574753954000000000');

\set ON_ERROR_STOP 0
CALL influxdb.process_line('testing', E'cpu,cpu=cpu0,host=fury usage_system=2.04,usage_user=5.40 1574753954000000000');
\set ON_ERROR_STOP 1

\x on
select * from testing.disk;
\x off

create table testing.magic(_time timestamp, level int, _tags jsonb, _fields jsonb);

CALL influxdb.process_line('testing', E'magic,level=0,path=0i free=527806464i,total=0i 1574753954000000000');
CALL influxdb.process_line('testing', E'magic,level=foo,path=0i free=527806464i,total=0i 1574753955000000000');
CALL influxdb.process_line('testing', E'magic,path=0i level=1,free=527806464i,total=0i 1574753956000000000');
CALL influxdb.process_line('testing', E'magic,level=2,path=0i level=3,free=527806464i,total=0i 1574753957000000000');

\x on
select * from testing.magic;
\x off

create table testing.all_types(_time timestamp, f_int int, f_float double precision, f_bool bool, f_text text);

CALL influxdb.process_line('testing', 'all_types f_int=123456789i,f_bool=True,f_text=magic 1574753954000000000');
CALL influxdb.process_line('testing', 'all_types f_int=123456789u,f_bool=True,f_text="more magic" 1574753955000000000');
CALL influxdb.process_line('testing', 'all_types f_int=123456789,f_bool=False,f_text=less\ magic 1574753956000000000');
CALL influxdb.process_line('testing', 'all_types f_float=3.14,f_bool=False,f_text=magic 1574753956000000000');

\x on
select * from testing.all_types;
\x off

drop schema testing cascade;
drop extension influxdb;
