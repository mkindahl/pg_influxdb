#ifndef INFLUXDB_TABLE_H_
#define INFLUXDB_TABLE_H_

#include <postgres.h>

#include "parser.h"

extern Oid InfluxCreateTable(Oid nspid, InfluxDataPoint* data_point,
                             bool raise_error);

#endif /* INFLUXDB_TABLE_H_ */
