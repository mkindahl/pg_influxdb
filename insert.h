#ifndef INFLUXDB_INSERT_H_
#define INFLUXDB_INSERT_H_

#include <postgres.h>

#include "parser.h"

void InfluxInsertDataPoint(Oid nspid, InfluxDataPoint* data_point,
                           bool raise_error);

#endif /* INFLUXDB_INSERT_H_ */
