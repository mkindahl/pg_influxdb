create extension influxdb;

create schema testing;

create table testing.disk(_time timestamptz, _tags jsonb, _fields jsonb);

CALL influxdb.process_line('testing', E'disk,mode=rw,path=/boot/efi free=527806464i,inodes_free=i,total=0i,used_percent=1.4929822952022749 1574753954000000000');
CALL influxdb.process_line('testing', E'disk,mode=0 free=527806464i,total=0i 1574753954000000000');
CALL influxdb.process_line('testing', E'disk,mode=0,path=0i free=527806464i,total=0i 1574753954000000000');

\set ON_ERROR_STOP 0
CALL influxdb.process_line('testing', E'cpu,cpu=cpu0,host=fury usage_system=2.04,usage_user=5.40 1574753954000000000');
\set ON_ERROR_STOP 1

\x on
SELECT * FROM testing.disk;
\x off

