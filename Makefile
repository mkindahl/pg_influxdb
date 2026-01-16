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
OBJS = influxdb.o parser.o tokenizer_lex.o utils.o plans.o insert.o table.o network.o http_parser.o http_worker.o

VERSION_influxdb = $(shell perl -ne 'print "$$1" if /^default_version.*(\d+\.\d+)/' influxdb.control)

EXTENSION = influxdb
DATA_built = influxdb--$(VERSION_influxdb).sql
PGFILEDESC = "influxdb - InfluxDB web interface to PostgreSQL"

REGRESS = tokenizer parser process create

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

influxdb--$(VERSION_influxdb).sql: influxdb.sql
	cp $< $@

tokenizer_lex.c tokenizer_lex.h: tokenizer_lex.l

http_parser.o: http_parser.c http_parser.h
http_worker.o: http_worker.c http_worker.h http_parser.h config.h \
 network.h
influxdb.o: influxdb.c influxdb.h config.h http_worker.h http_parser.h \
 insert.h parser.h
insert.o: insert.c insert.h parser.h influxdb.h plans.h table.h utils.h
network.o: network.c network.h
parser.o: parser.c parser.h
plans.o: plans.c plans.h
table.o: table.c table.h parser.h
tokenizer_lex.o: tokenizer_lex.c parser.h influxdb.h
utils.o: utils.c utils.h parser.h
