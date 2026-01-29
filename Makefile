# InfluxDB API to PostgreSQL. Copyright (C) 2025 Mats Kindahl
#    
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Affero General Public License for more details.
#    
# You should have received a copy of the GNU Affero General Public
# License along with this program.  If not, see
# <https://www.gnu.org/licenses/>.

MODULE_big = influxdb
OBJS_http = src/http/http_parser.o src/http/worker.o
OBJS_proto = src/proto/tokenizer_lex.o src/proto/parser.o 
OBJS_exec = src/exec/plans.o src/exec/insert.o src/exec/table.o
OBJS = src/influxdb.o src/utils.o src/network.o src/debug.o $(OBJS_http) $(OBJS_proto) $(OBJS_exec)

VERSION_influxdb = $(shell perl -ne 'print "$$1" if /^default_version.*(\d+\.\d+)/' influxdb.control)

EXTENSION = influxdb
DATA_built = influxdb--$(VERSION_influxdb).sql
PGFILEDESC = "influxdb - InfluxDB web interface to PostgreSQL"

REGRESS = tokenizer parser process create
TAP_TESTS = 1

PG_CPPFLAGS = -Isrc

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

influxdb--$(VERSION_influxdb).sql: influxdb.sql
	cp $< $@

src/protocol/tokenizer_lex.c src/protocol/tokenizer_lex.h: src/protocol/tokenizer_lex.l

parser.o: src/proto/parser.c src/proto/parser.h
tokenizer_lex.o: src/proto/tokenizer_lex.c src/proto/parser.h \
 src/influxdb.h
worker.o: src/http/worker.c src/http/worker.h src/http/http_parser.h \
 src/config.h src/http/http_parser.h src/influxdb.h src/network.h \
 src/utils.h
http_parser.o: src/http/http_parser.c src/http/http_parser.h
plans.o: src/exec/plans.c src/exec/plans.h
table.o: src/exec/table.c src/exec/table.h src/proto/parser.h
insert.o: src/exec/insert.c src/exec/insert.h src/proto/parser.h \
 src/influxdb.h src/exec/plans.h src/exec/table.h
influxdb.o: src/influxdb.c src/influxdb.h src/config.h src/http/worker.h \
 src/http/http_parser.h
network.o: src/network.c src/network.h
utils.o: src/utils.c src/utils.h
