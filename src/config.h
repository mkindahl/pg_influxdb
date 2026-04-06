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

#ifndef CONFIG_H_
#define CONFIG_H_

#define INFLUXDB_DEFAULT_HTTP_SERVICE "8086"
#define INFLUXDB_DEFAULT_HTTP_RESTART_TIME 20
#define INFLUXDB_DEFAULT_SCHEMA_NAME "measurements"
#define INFLUXDB_HTTP_FUNCTION_NAME "InfluxHttpWorkerMain"
#define INFLUXDB_LIBRARY_NAME "influxdb"

#define INFLUXDB_DEFAULT_UDP_SERVICE "8089"
#define INFLUXDB_DEFAULT_UDP_READ_BUFFER 0
#define INFLUXDB_DEFAULT_UDP_WORKERS 0
#define INFLUXDB_UDP_FUNCTION_NAME "InfluxUdpWorkerMain"

#endif /* CONFIG_H_ */
