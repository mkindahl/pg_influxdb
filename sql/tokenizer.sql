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

create table samples(
  sample_id serial,
  sample_text text
);

insert into samples(sample_text) values
       ('myMeasurement fieldKey=1u'),
       ('myMeasurement fieldKey=12485903u'),
       ('myMeasurement fieldKey=true'),
       ('myMeasurement fieldKey=false'),
       ('myMeasurement fieldKey=t'),
       ('myMeasurement fieldKey=f'),
       ('myMeasurement fieldKey=TRUE'),
       ('myMeasurement fieldKey=FALSE'),
       ('myMeasurement fieldKey=tRue'),
       ('myMeasurement fieldKey=fAlse'),
       ('myMeasurement fieldKey="this is a string"'),
       ('myMeasurementName fieldKey="fieldValue" 1556813561098000000'),
       ('my\ Measurement fieldKey="string value"'),
       ('myMeasurement fieldKey="\"string\" within a string"'),
       ($$myMeasurement fieldKey='"string" within a string'$$),
       ('myMeasurement,tag\ Key1=tag\ Value1,tag\ Key2=tag\ Value2 fieldKey=100'),
       ('myMeasurement,tagKey=🍭 fieldKey="Launch 🚀" 1556813561098000000'),
       ('myMeasurement,tag1=value1,tag2=value2 fieldKey="fieldValue" 1556813561098000000'),
       ('myMeasurement fieldKey=1.0'),
       ('myMeasurement fieldKey=1'),
       ('myMeasurement fieldKey=-1.234456e+78'),
       ('myMeasurement fieldKey=1i'),
       ('myMeasurement fieldKey=12485903i'),
       ('myMeasurement fieldKey=-12485903i');

\x on
with
  tokens as (
    select sample_id,
           sample_text,
           (influxdb.tokenize(sample_text)).*
      from samples
  )
select sample_id,
       sample_text,
       array_agg(kind),
       array_agg(value)
  from tokens
group by sample_id, sample_text
order by sample_id;
\x off

drop table samples;

set influxdb.keep_quotes to on;
select * from influxdb.tokenize('myMeasurement fieldKey="this is a string"');
select * from influxdb.tokenize($$myMeasurement fieldKey='this is a string'$$);

-- These should generate reasonable error messages
\set ON_ERROR_STOP 0
-- Non-terminated string should generate an error.
select * from influxdb.tokenize('myMeasurement fieldKey="this is a string');
select * from influxdb.tokenize($$myMeasurement fieldKey='this is a string$$);
-- Newlines inside strings are not allowed by the protocol.
select * from influxdb.tokenize(E'myMeasurement fieldKey="this is a\nstring"');
\set ON_ERROR_STOP 1

drop extension influxdb;
