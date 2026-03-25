# Copyright (C) 2025 Mats Kindahl
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
OBJS_http = src/http/http_parser.o src/http/params.o src/http/worker.o
OBJS_udp = src/udp/worker.o
OBJS_proto = src/proto/tokenizer_lex.o src/proto/parser.o
OBJS_exec = src/exec/plans.o src/exec/insert.o src/exec/table.o
OBJS_common = src/common/utils.o
OBJS = src/influxdb.o src/network.o src/debug.o $(OBJS_common) $(OBJS_http) $(OBJS_udp) $(OBJS_proto) $(OBJS_exec)

VERSION_influxdb = $(shell perl -ne 'print "$$1" if /^default_version.*(\d+\.\d+)/' influxdb.control)

PERL_FILES = $(wildcard t/*.pl perl/InfluxDB/*.pm perl/InfluxDB/Test/*.pm)

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

format-perl:
	perltidy $(PERL_FILES)

src/protocol/tokenizer_lex.c src/protocol/tokenizer_lex.h: src/protocol/tokenizer_lex.l

src/proto/parser.o: src/proto/parser.c src/proto/parser.h
src/proto/tokenizer_lex.o: src/proto/tokenizer_lex.c src/proto/parser.h \
 src/influxdb.h
src/http/worker.o: src/http/worker.c src/http/worker.h src/http/http_parser.h \
 src/config.h src/http/http_parser.h src/influxdb.h src/network.h \
 src/common/utils.h
src/http/http_parser.o: src/http/http_parser.c src/http/http_parser.h
src/http/params.o: src/http/params.c src/http/params.h src/config.h src/influxdb.h \
 src/common/utils.h
src/exec/plans.o: src/exec/plans.c src/exec/plans.h
src/exec/table.o: src/exec/table.c src/exec/table.h src/proto/parser.h
src/exec/insert.o: src/exec/insert.c src/exec/insert.h src/proto/parser.h \
 src/influxdb.h src/exec/plans.h src/exec/table.h
src/udp/worker.o: src/udp/worker.c src/udp/worker.h src/config.h \
 src/influxdb.h src/network.h src/exec/insert.h
src/influxdb.o: src/influxdb.c src/influxdb.h src/config.h src/http/worker.h \
 src/http/http_parser.h src/udp/worker.h
network.o: src/network.c src/network.h
src/common/utils.o: src/common/utils.c src/common/utils.h
