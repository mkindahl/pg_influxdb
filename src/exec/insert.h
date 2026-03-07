/*
 * InfluxDB API to PostgreSQL. Copyright (C) 2025 Mats Kindahl
 *
 * This program is free software: you can redistribute it and/or
 * modify it under the terms of the GNU Affero General Public License
 * as published by the Free Software Foundation, either version 3 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public
 * License along with this program.  If not, see
 * <https://www.gnu.org/licenses/>.
 */

#ifndef INFLUXDB_INSERT_H_
#define INFLUXDB_INSERT_H_

#include <postgres.h>

#include "proto/parser.h"

extern Datum process_text(PG_FUNCTION_ARGS);

extern void process_text_internal(Oid nspid, char* buf, size_t len,
                                  int64 precision_multiplier);
extern void InfluxInsertDataPoint(Oid nspid, InfluxDataPoint* data_point,
                                  bool raise_error,
                                  int64 precision_multiplier);

#endif /* INFLUXDB_INSERT_H_ */
