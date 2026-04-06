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

#ifndef HTTP_WORKER_H_
#define HTTP_WORKER_H_

#include <postgres.h>

#include <c.h>
#include <postmaster/bgworker.h>
#include <utils/hsearch.h>
#include <utils/jsonb.h>

#include "http_parser.h"

/*
 * Struct: InfluxHttpConnectionEntry
 *
 * Connection state for a single connection. The connection state has
 * a separate memory context with a lifetime as long as the
 * connection.
 *
 * Note:
 *   Note that this structure is stored in a hash, so the order of the
 *   fields are important. They key fields should always be first.
 *
 */
typedef struct InfluxHttpConnectionEntry {
  /* Key fields */
  int read_fd;

  /* Value fields */
  http_parser_settings settings;
  http_parser parser;
  MemoryContext mcxt;
} InfluxHttpConnectionEntry;

/*
 * Struct: InfluxHttpWorkerState
 *
 * State for the HTTP worker.
 */
typedef struct InfluxHttpWorkerState {
  int epoll_fd;
  int listen_fd;
  HTAB* http_connection_hash;
} InfluxHttpWorkerState;

/*
 * Struct: InfluxHttpHeaderData
 *
 * Headers for a HTTP request or response.
 */
typedef struct InfluxHttpHeaderData {
  const char* name;
  const char* value;
} InfluxHttpHeaderData;

/*
 * Enum: State for an HTTP worker connection.
 */
typedef enum InfluxHttpRequestType {
  OPERATION_UNDEF,
  OPERATION_WRITE,
  OPERATION_PING,
  OPERATION_QUERY,
} InfluxHttpRequestType;

/*
 * Enum: State for an HTTP worker connection.
 */
typedef enum InfluxHttpHeaderState {
  HEADER_STATE_NONE,
  HEADER_STATE_CONTENT_ENCODING,
  HEADER_STATE_AUTHORIZATION,
} InfluxHttpHeaderState;

/*
 * Struct: Data for an InfluxDB HTTP request.
 */
typedef struct InfluxHttpRequestData {
  MemoryContext mcxt; /* Memory context for this request's allocations */
  InfluxHttpRequestType type; /* Endpoint type, e.g, a write endpoint */
  Oid nspoid;                 /* Namespace OID for the "database" */
  int64
      precision_multiplier; /* Timestamp precision multiplier to nanoseconds */
  const char* error;        /* Error message for the client, or NULL */
  bool complete;            /* Set by on_message_complete callback */
  bool is_gzip;             /* Content-Encoding: gzip */
  StringInfo remaining;     /* Leftover partial line from on_body */
  InfluxHttpHeaderState header_state; /* Which header we're currently parsing */
  bool auth_failed;                   /* Auth check failed */
  bool query_ok;            /* Whether the query executed successfully */
  char* auth_header;        /* Authorization header value */
  char* query_user;         /* u= query parameter */
  char* query_pass;         /* p= query parameter */
  char* query_error;        /* error message if query failed */
  const char* allow_header; /* Allow header for 405 responses */
} InfluxHttpRequestData;

extern PGDLLEXPORT void InfluxHttpWorkerMain(Datum arg);

extern void InfluxHttpWorkerInit(BackgroundWorker* worker);
extern void InfluxHttpWorkerProcessData(InfluxHttpWorkerState* state, int fd);
extern void InfluxHttpWorkerInitState(InfluxHttpWorkerState* state);
extern void InfluxHttpWorkerConnectionAccept(InfluxHttpWorkerState* state);
extern void InfluxHttpWorkerConnectionCreate(InfluxHttpWorkerState* state,
                                             int fd);
extern void InfluxHttpWorkerConnectionDelete(InfluxHttpWorkerState* state,
                                             int fd);
extern void InfluxHttpWorkerConnectionInit(InfluxHttpConnectionEntry* entry);
extern InfluxHttpConnectionEntry* InfluxHttpWorkerConnectionFetch(
    InfluxHttpWorkerState* state, int fd);
extern void InfluxHttpWorkerSendResponse(const InfluxHttpWorkerState* state,
                                         int fd, int status_code,
                                         const InfluxHttpHeaderData field[],
                                         size_t nfields, const char* content);
extern void InfluxHttpWorkerSendErrorResponse(InfluxHttpWorkerState* state,
                                              int fd, int status_code,
                                              Jsonb* content);

#endif /* HTTP_WORKER_H_ */
