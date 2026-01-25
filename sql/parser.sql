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

create extension if not exists influxdb;

select * from influxdb.parse_text('myMeasurement fieldKey=1u');
select * from influxdb.parse_text('myMeasurement fieldKey=12485903u');
select * from influxdb.parse_text('myMeasurement fieldKey=true');
select * from influxdb.parse_text('myMeasurement fieldKey=false');
select * from influxdb.parse_text('myMeasurement fieldKey=t');
select * from influxdb.parse_text('myMeasurement fieldKey=f');
select * from influxdb.parse_text('myMeasurement fieldKey=TRUE');
select * from influxdb.parse_text('myMeasurement fieldKey=FALSE');
select * from influxdb.parse_text('myMeasurement fieldKey=tRue');
select * from influxdb.parse_text('myMeasurement fieldKey=fAlse');
select * from influxdb.parse_text('myMeasurement fieldKey="this is a string"');
select * from influxdb.parse_text('myMeasurementName fieldKey="fieldValue" 1556813561098000000');
select * from influxdb.parse_text('my\ Measurement fieldKey="string value"');
select * from influxdb.parse_text('myMeasurement fieldKey="\"string\" within a string"');
select * from influxdb.parse_text($$myMeasurement fieldKey='"string" within a string'$$);
select * from influxdb.parse_text('myMeasurement,tag\ Key1=tag\ Value1,tag\ Key2=tag\ Value2 fieldKey=100');
select * from influxdb.parse_text('myMeasurement,tag1=value1,tag2=value2 fieldKey="fieldValue" 1556813561098000000');
select * from influxdb.parse_text('myMeasurement fieldKey=1.0');
select * from influxdb.parse_text('myMeasurement fieldKey=1');
select * from influxdb.parse_text('myMeasurement fieldKey=-1.234456e+78');
select * from influxdb.parse_text('myMeasurement fieldKey=1i');
select * from influxdb.parse_text('myMeasurement fieldKey=12485903i');
select * from influxdb.parse_text('myMeasurement fieldKey=-12485903i');
select * from influxdb.parse_text('myMeasurement,tagKey=🍭 fieldKey="Launch 🚀" 1556813561098000000');
select * from influxdb.parse_text('disk,mode=0,path=0i free=527806466i,total=10i 1574753955000000000
disk,mode=0,path=0i free=527806499i,total=20i 1574753956000000000');

-- Different variations of line endings for multi-line texts that has
-- caused problems. We allow and ignore blanks and the end of the
-- line, and also allow missing timestamps.
select * from influxdb.parse_text(E'cpu,mode=0 load=1.2 1556814561098000000\ncpu,mode=1 load=1.5\n');
select * from influxdb.parse_text(E'cpu,mode=1 load=1.2 1556814561098000000 \ncpu,mode=1 load=1.5\n');
select * from influxdb.parse_text(E'cpu,mode=2 load=1.2  \ncpu,mode=1 load=1.5 1556814561098000000\n');
select * from influxdb.parse_text(E'cpu,mode=3 load=1.2  \ncpu,mode=1 load=1.5 1556814561098000000 \n');
select * from influxdb.parse_text(E'cpu,mode=4 load=1.2  \ncpu,mode=1 load=1.5 1556814561098000000 ');
select * from influxdb.parse_text(E'cpu,mode=5 load=1.2  \ncpu,mode=1 load=1.5');
select * from influxdb.parse_text(E'cpu,mode=6 load=1.2  \ncpu,mode=1 load=1.5\n');
select * from influxdb.parse_text(E'cpu,mode=7 load=1.2\ncpu,mode=1 load=1.5\n');
select * from influxdb.parse_text(E'cpu,mode=7 load=1.2\ncpu,mode=1 load=1.5');
select * from influxdb.parse_text(E'cpu load=9.99\ncpu load=9.98');

drop extension influxdb;
