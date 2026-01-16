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

#ifndef HTTP_WORKER_H_
#define HTTP_WORKER_H_

#include <postgres.h>

#include <c.h>
#include <postmaster/bgworker.h>
#include <utils/hsearch.h>

#include "http_parser.h"

/*
 * Struct: HttpConnectionEntry
 *
 * Connection state for a single connection.
 */
typedef struct HttpConnectionEntry {
  int read_fd;
  http_parser_settings settings;
  http_parser parser;
} HttpConnectionEntry;

/*
 * Struct: HttpWorkerState
 *
 * State for the HTTP worker.
 */
typedef struct InfluxHttpWorkerState {
  int epoll_fd;
  int listen_fd;
  HTAB* http_connection_hash;
} InfluxHttpWorkerState;

extern PGDLLEXPORT void InfluxHttpWorkerMain(Datum arg);

extern void InfluxHttpWorkerInit(BackgroundWorker* worker);
extern void InfluxHttpWorkerAcceptConnection(InfluxHttpWorkerState* state);
extern void InfluxHttpWorkerProcessData(InfluxHttpWorkerState* state,
                                        int client_fd);
extern void InfluxHttpWorkerInitState(InfluxHttpWorkerState* state);
extern HttpConnectionEntry* InfluxHttpWorkerAddConnection(
    InfluxHttpWorkerState* state, int fd);
extern HttpConnectionEntry* InfluxHttpWorkerDelConnection(
    InfluxHttpWorkerState* state, int fd);
extern void InfluxHttpWorkerSendResponse(InfluxHttpWorkerState* state,
                                         int client_fd, int status_code,
                                         const char* reason,
                                         const char* content_type,
                                         const char* body);
#endif /* HTTP_WORKER_H_ */
