/*
 * Copyright (C) 2025 Mats Kindahl
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

#ifndef INFLUXDB_INFLUXDB_H_
#define INFLUXDB_INFLUXDB_H_

#include <postgres.h>
#include <fmgr.h>

#include <stdbool.h>

extern bool influxdb_keep_quotes;
extern bool influxdb_auto_create_table;
extern char* influxdb_http_service;
extern char* influxdb_database;
extern int influxdb_http_workers;
extern int influxdb_http_worker_restart_time;
extern bool influxdb_http_auth;
#ifdef INFLUXDB_USE_SSL
extern bool influxdb_https;
extern char* influxdb_https_service;
#endif

extern char* influxdb_udp_service;
extern char* influxdb_udp_schema;
extern int influxdb_udp_read_buffer;
extern int influxdb_udp_workers;

#endif /* INFLUXDB_INFLUXDB_H_ */
