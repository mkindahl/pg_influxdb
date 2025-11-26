MODULE_big = influxdb
OBJS = influxdb.o parser.o tokenizer_lex.o utils.o plans.o insert.o table.o

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

influxdb.o: influxdb.c parser.h utils.h
parser.o: parser.c parser.h
tokenizer_lex.o: tokenizer_lex.c parser.h influxdb.h
utils.o: utils.c utils.h parser.h
