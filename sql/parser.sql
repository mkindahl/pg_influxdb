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

select * from influxdb.parse_line('myMeasurement fieldKey=1u');
select * from influxdb.parse_line('myMeasurement fieldKey=12485903u');
select * from influxdb.parse_line('myMeasurement fieldKey=true');
select * from influxdb.parse_line('myMeasurement fieldKey=false');
select * from influxdb.parse_line('myMeasurement fieldKey=t');
select * from influxdb.parse_line('myMeasurement fieldKey=f');
select * from influxdb.parse_line('myMeasurement fieldKey=TRUE');
select * from influxdb.parse_line('myMeasurement fieldKey=FALSE');
select * from influxdb.parse_line('myMeasurement fieldKey=tRue');
select * from influxdb.parse_line('myMeasurement fieldKey=fAlse');
select * from influxdb.parse_line('myMeasurement fieldKey="this is a string"');
select * from influxdb.parse_line('myMeasurementName fieldKey="fieldValue" 1556813561098000000');
select * from influxdb.parse_line('my\ Measurement fieldKey="string value"');
select * from influxdb.parse_line('myMeasurement fieldKey="\"string\" within a string"');
select * from influxdb.parse_line($$myMeasurement fieldKey='"string" within a string'$$);
select * from influxdb.parse_line('myMeasurement,tag\ Key1=tag\ Value1,tag\ Key2=tag\ Value2 fieldKey=100');
select * from influxdb.parse_line('myMeasurement,tag1=value1,tag2=value2 fieldKey="fieldValue" 1556813561098000000');
select * from influxdb.parse_line('myMeasurement fieldKey=1.0');
select * from influxdb.parse_line('myMeasurement fieldKey=1');
select * from influxdb.parse_line('myMeasurement fieldKey=-1.234456e+78');
select * from influxdb.parse_line('myMeasurement fieldKey=1i');
select * from influxdb.parse_line('myMeasurement fieldKey=12485903i');
select * from influxdb.parse_line('myMeasurement fieldKey=-12485903i');
select * from influxdb.parse_line('myMeasurement,tagKey=🍭 fieldKey="Launch 🚀" 1556813561098000000');
select * from influxdb.parse_line('disk,mode=0,path=0i free=527806466i,total=10i 1574753955000000000
disk,mode=0,path=0i free=527806499i,total=20i 1574753956000000000');

drop extension influxdb;
