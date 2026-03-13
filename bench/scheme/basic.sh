#!/bin/bash

function setup_scheme () {
    psql -q <<EOF
CREATE SCHEMA IF NOT EXISTS magic;

DROP VIEW IF EXISTS combined;
DROP TABLE IF EXISTS magic.cpu;
DROP TABLE IF EXISTS magic.disk;
DROP TABLE IF EXISTS magic.swap;
DROP TABLE IF EXISTS magic.diskio;

CREATE TABLE magic.cpu (
    _time timestamptz,
    _tags jsonb,
    _fields jsonb
);

CREATE TABLE magic.swap (
    _time timestamptz,
    _tags jsonb,
    _fields jsonb
);

CREATE TABLE magic.disk (
    _time timestamptz,
    _tags jsonb,
    _fields jsonb
);

CREATE TABLE magic.diskio (
    _time timestamptz,
    _tags jsonb,
    _fields jsonb
);

CREATE VIEW combined AS
    SELECT _time, _tags, _fields FROM magic.cpu
  UNION ALL
    SELECT _time, _tags, _fields FROM magic.swap
  UNION ALL
    SELECT _time, _tags, _fields FROM magic.disk
  UNION ALL
    SELECT _time, _tags, _fields FROM magic.diskio;
EOF
}

function reset_scheme () {
    psql -q -c 'TRUNCATE magic.swap, magic.cpu, magic.disk, magic.diskio'
}

function generate_data () {
    LC_NUMERIC=C awk -v count="$COUNT" 'BEGIN {
        srand()
        tables[0] = "cpu"
        tables[1] = "swap"
        tables[2] = "disk"
        tables[3] = "diskio"
        hosts[0] = "host0"
        hosts[1] = "host1"
        hosts[2] = "host2"
        for (i = 0; i < count; i++) {
            t = tables[int(rand() * 4)]
            h = hosts[int(rand() * 3)]
            ts = systime() * 1000000000
            if (t == "cpu") {
                printf "cpu,cpu=cpu%d,host=%s usage_idle=%.2f,usage_iowait=%.2f,usage_nice=%.2f,usage_system=%.2f,usage_user=%.2f %d\n", \
                    int(rand() * 4), h, rand() * 10, rand() * 10, rand() * 10, rand() * 10, rand() * 10, ts
            } else if (t == "swap") {
                total = 8000000000
                used = int(rand() * total)
                free = total - used
                printf "swap,host=%s free=%di,total=%di,used=%di,used_percent=%.2f %d\n", \
                    h, free, total, used, (used / total) * 100, ts
            } else if (t == "disk") {
                total = 500000000000
                used = int(rand() * total)
                free = total - used
                printf "disk,device=sda1,fstype=ext4,host=%s,mode=rw,path=/ free=%di,inodes_free=%di,inodes_total=10000000i,inodes_used=%di,total=%di,used=%di,used_percent=%.2f %d\n", \
                    h, free, 10000000 - int(rand() * 1000000), int(rand() * 1000000), total, used, (used / total) * 100, ts
            } else {
                printf "diskio,host=%s,name=sda io_time=%di,read_bytes=%di,write_bytes=%di %d\n", \
                    h, int(rand() * 100000), int(rand() * 1000000000), int(rand() * 1000000000), ts
            }
        }
    }'
}

# Wait until the count is stable.
#
# Then all lines should have been processed. We start at -1 since a
# very fast check might give zero back.
function wait_until_stable () {
    echo -n "Waiting.."
    prev=-1
    while true; do
	cnt=$(psql -qt -c "SELECT count(*) FROM combined")
	if [[ "$cnt" -eq "$prev" ]]; then
	    break
	fi
	prev=$cnt
	echo -n "."
	sleep 1
    done
    echo "stable (at $cnt)"
}

function record_measurements () {
    psql -q <<EOF
INSERT INTO measurements(time, count, total, version, scheme)
SELECT now(), count(*), $COUNT, '$VERSION', '$SCHEME' FROM combined
EOF
}
