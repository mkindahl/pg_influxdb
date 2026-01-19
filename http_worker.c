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

#include "http_worker.h"

#include <postgres.h>

#include <access/xact.h>
#include <catalog/namespace.h>
#include <executor/spi.h>
#include <pgstat.h>
#include <postmaster/bgworker.h>
#include <postmaster/interrupt.h>
#include <storage/ipc.h>
#include <utils/backend_status.h>
#include <utils/guc.h>
#include <utils/hsearch.h>
#include <utils/jsonb.h>
#include <utils/memutils.h>
#include <utils/resowner.h>

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <sys/epoll.h>
#include <sys/socket.h>

#include "config.h"
#include "http_parser.h"
#include "influxdb.h"
#include "network.h"
#include "utils.h"

#include <arpa/inet.h>
#include <netinet/in.h>

#define BUFFER_SIZE (8 * 1024)

typedef enum InfluxHttpRequestType {
  OPERATION_UNDEF,
  OPERATION_WRITE,
} InfluxHttpRequestType;

typedef struct InfluxHttpRequestData {
  InfluxHttpRequestType type;
} InfluxHttpRequestData;

static void HttpWorkerInsertMeasurements(const char* buf, size_t buflen) {
  int err;
  Oid nspoid;

  pgstat_report_activity(STATE_RUNNING, "initializing worker_spi schema");

  SetCurrentStatementStartTimestamp();
  StartTransactionCommand();

  if ((err = SPI_connect()) != SPI_OK_CONNECT)
    elog(ERROR, "SPI_connect failed: %s", SPI_result_code_string(err));

  PushActiveSnapshot(GetTransactionSnapshot());

  nspoid = get_namespace_oid(influxdb_schema_name, false);
  elog(LOG, "processing text:\n%s", buf);
  process_text_internal(nspoid, (char*)buf, buflen);

  if ((err = SPI_finish()) != SPI_OK_FINISH)
    elog(ERROR, "SPI_finish failed: %s", SPI_result_code_string(err));

  PopActiveSnapshot();
  CommitTransactionCommand();

  pgstat_report_activity(STATE_IDLE, NULL);
}

static int on_url(http_parser* parser, const char* at, size_t length) {
  const char write[] = "/write";
  if (strncmp(at, write, sizeof(write) - 1) == 0) {
    InfluxHttpRequestData* data = parser->data;
    data->type = OPERATION_WRITE;
    return 0; /*  All OK */
  } else {
    return 1; /* Error */
  }
}

static int on_body(http_parser* parser, const char* buf, size_t len) {
  InfluxHttpRequestData* data = parser->data;
  switch (data->type) {
    case OPERATION_WRITE:
      HttpWorkerInsertMeasurements(buf, len);
      return 0;
    default:
      return 1;
  }
}

/*
 * Function: InfluxHttpWorkerSendResponse
 *
 * We always close the connection so the connection close header field
 * should be added when calling this function and the connection
 * shutdown.
 *
 * If we want to support keep-alive connections, we need to handle
 * that by remembering the value in the request header and using it
 * here.
 */
void InfluxHttpWorkerSendResponse(const InfluxHttpWorkerState* state,
                                  int client_fd, int status_code,
                                  const char* reason,
                                  const InfluxHttpHeaderData field[],
                                  size_t nfields, const char* body) {
  ssize_t sent;
  StringInfoData response;
  time_t now = time(NULL);
  char buf[128];

  Assert(content_type != NULL);

  initStringInfo(&response);
  appendStringInfo(&response, "HTTP/1.1 %d %s\r\n", status_code, reason);

  if (field) {
    Assert(nfields > 0);
    for (size_t i = 0; i < nfields; ++i) {
      appendStringInfo(&response, "%s: %s\r\n", field[i].name, field[i].value);
    }
  }

  /*
   * Add current date to the response.
   *
   * TODO: Switch to the recommended format rather than one of the
   * obsolete (but supported) formats.
   *
   * Function asctime() adds a newline last, so we remove the
   * terminating newline and add a proper CRLF below.
   */
  asctime_r(localtime(&now), buf);
  buf[strlen(buf) - 1] = '0';
  appendStringInfo(&response, "Date: %s\r\n", buf);

  if (body) {
    size_t body_length = strlen(body);
    appendStringInfo(&response, "Content-Length: %lu\r\n", body_length);
  }

  appendStringInfoString(&response, "\r\n");

  if (body) {
    appendStringInfoString(&response, body);
    appendStringInfoString(&response, "\r\n");
  }

  elog(DEBUG1, "sending response:\n%s", response.data);

  sent = write(client_fd, response.data, response.len);
  if (sent != response.len)
    ereport(LOG,
            errcode_for_socket_access(),
            errmsg("sent %ld bytes of response but should have sent %d: %m",
                   sent,
                   response.len));

  resetStringInfo(&response);
}

HttpConnectionEntry* InfluxHttpWorkerDelConnection(InfluxHttpWorkerState* state,
                                                   int fd) {
  HttpConnectionEntry* entry;
  elog(DEBUG1,
       "%s: removing file descriptor %d from epoll set %d",
       __func__,
       fd,
       state->epoll_fd);

  entry = hash_search(state->http_connection_hash, &fd, HASH_REMOVE, NULL);

  if (epoll_ctl(state->epoll_fd, EPOLL_CTL_DEL, fd, NULL) == -1)
    ereport(ERROR,
            errcode_for_socket_access(),
            errmsg("could not remove file descriptor %d from epoll set %d: %m",
                   fd,
                   state->epoll_fd));

  shutdown(fd, SHUT_RDWR);
  close(fd);

  return entry;
}

static void extend_epoll_set(InfluxHttpWorkerState* state, int fd) {
  struct epoll_event ev;
  ev.events = EPOLLIN;
  ev.data.fd = fd;

  elog(DEBUG1,
       "%s: adding file descriptor %d to epoll set %d",
       __func__,
       fd,
       state->epoll_fd);

  if (epoll_ctl(state->epoll_fd, EPOLL_CTL_ADD, fd, &ev) == -1)
    ereport(ERROR,
            errcode_for_socket_access(),
            errmsg("could not add file descriptor %d to epoll set %d: %m",
                   fd,
                   state->epoll_fd));
}

HttpConnectionEntry* InfluxHttpWorkerAddConnection(InfluxHttpWorkerState* state,
                                                   int fd) {
  HttpConnectionEntry* entry;
  bool found;

  extend_epoll_set(state, fd);

  if (state->http_connection_hash == NULL) {
    HASHCTL ctl = {.keysize = sizeof(int),
                   .entrysize = sizeof(HttpConnectionEntry)};
    state->http_connection_hash =
        hash_create("http_connections", 8, &ctl, HASH_ELEM | HASH_BLOBS);
  }

  entry = hash_search(state->http_connection_hash, &fd, HASH_ENTER, &found);
  if (found)
    elog(WARNING, "adding connection %d a second time, not changing state", fd);

  memset(&entry->settings, 0, sizeof(entry->settings));
  entry->settings.on_url = on_url;
  entry->settings.on_body = on_body;
  http_parser_init(&entry->parser, HTTP_REQUEST);
  entry->parser.data = palloc0(sizeof(InfluxHttpRequestData));
  return entry;
}

void InfluxHttpWorkerInitState(InfluxHttpWorkerState* state) {
  struct sockaddr_in addr;
  socklen_t addrlen = sizeof(addr);

  memset(state, 0, sizeof(*state));

  elog(DEBUG1, "%s: initializing HTTP worker state", __func__);

  /* Set up epoll socket */
  state->epoll_fd = epoll_create1(0);
  if (state->epoll_fd == -1)
    ereport(LOG,
            errcode_for_socket_access(),
            errmsg("could not create epoll socket: %m"));

  /* Set up listen socket */
  state->listen_fd = network_listener_create(
      influxdb_http_service, (struct sockaddr*)&addr, &addrlen);
  if (state->listen_fd == -1)
    ereport(ERROR,
            errcode_for_socket_access(),
            errmsg("could not create socket: %m"));

  extend_epoll_set(state, state->listen_fd);

  elog(LOG, "InfluxDB HTTP Worker listening on port %d", addr.sin_port);
}

static HttpConnectionEntry* http_worker_get_connection(
    InfluxHttpWorkerState* state, int key) {
  if (state->http_connection_hash == NULL) {
    HASHCTL ctl = {.keysize = sizeof(int),
                   .entrysize = sizeof(HttpConnectionEntry)};
    state->http_connection_hash =
        hash_create("http_connections", 8, &ctl, HASH_ELEM | HASH_BLOBS);
  }

  return hash_search(state->http_connection_hash, &key, HASH_FIND, NULL);
}

void InfluxHttpWorkerAcceptConnection(InfluxHttpWorkerState* state) {
  while (1) {
    struct sockaddr_in addr;
    socklen_t addrlen = sizeof(addr);
    int client_fd;
    char addr_text[INET_ADDRSTRLEN];

    client_fd = accept(state->listen_fd, (struct sockaddr*)&addr, &addrlen);
    if (client_fd == -1) {
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        break;
      } else {
        ereport(LOG,
                errcode_for_socket_access(),
                errmsg("failed to accept connection: %m"));
        break;
      }
    }

    inet_ntop(AF_INET, &addr.sin_addr, addr_text, sizeof(addr_text));
    elog(LOG, "accepted connection from %s", addr_text);

    if (set_nonblocking(client_fd) == -1) {
      perror("set_nonblocking");
      close(client_fd);
      continue;
    }

    InfluxHttpWorkerAddConnection(state, client_fd);
  }
}

/*
 * Function: influxdb_http_worker_process_data
 *
 * Process received data by feeding it into the associated parser.
 *
 * If the parser fails, it will send an error message back, shut down
 * the parser, and close the connection.
 */
void InfluxHttpWorkerProcessData(InfluxHttpWorkerState* state, int client_fd) {
  MemoryContext oldcontext = CurrentMemoryContext;
  ResourceOwner oldowner = CurrentResourceOwner;

  PG_TRY();
  {
    while (1) {
      char buffer[BUFFER_SIZE] = {0};
      ssize_t parsed, len;
      HttpConnectionEntry* entry;

      /* Not a datagram channel so recv and read are equivalent */
      len = read(client_fd, buffer, BUFFER_SIZE - 1);

      elog(DEBUG1, "received %ld bytes on %d:\n%s", len, client_fd, buffer);

      /* If all data is processed, we just send a response and return */
      if (len == 0 ||
          (len == -1 && (errno == EAGAIN || errno == EWOULDBLOCK))) {
        InfluxHttpHeaderData fields[] = {
            {"Connection", "close"},
        };

        InfluxHttpWorkerSendResponse(state,
                                     client_fd,
                                     204,
                                     "No Content",
                                     fields,
                                     sizeof(fields) / sizeof(*fields),
                                     NULL);
        InfluxHttpWorkerDelConnection(state, client_fd);
        return;
      }

      /* If we had an error, send a respose and close connection */
      if (len == -1)
        ereport(
            ERROR, errcode_for_socket_access(), errmsg("recv call failed: %m"));

      entry = http_worker_get_connection(state, client_fd);
      if (entry == NULL) {
        elog(LOG, "entry for file descriptor %d not found", client_fd);
        break;
      }

      parsed =
          http_parser_execute(&entry->parser, &entry->settings, buffer, len);

      elog(DEBUG1, "parsed %ld bytes of %ld", parsed, len);

      if (parsed != len)
        elog(ERROR,
             "HTTP error %s when parsing data from %d: %s",
             http_errno_name(HTTP_PARSER_ERRNO(&entry->parser)),
             entry->read_fd,
             http_errno_description(HTTP_PARSER_ERRNO(&entry->parser)));
    }
  }
  PG_CATCH();
  {
    StringInfo edata_text;
    ErrorData* edata;
    Jsonb* edata_jb;
    const InfluxHttpHeaderData fields[] = {
        {"Content-Type", "application/json"},
        {"Connection", "close"},
    };

    MemoryContextSwitchTo(oldcontext);
    edata_text = makeStringInfo();

    HOLD_INTERRUPTS();

    EmitErrorReport();
    AbortOutOfAnyTransaction();
    edata = CopyErrorData();
    FlushErrorState();

    RESUME_INTERRUPTS();

    elog(DEBUG1, "edata: level=%d, message=%s", edata->elevel, edata->message);

    MemoryContextSwitchTo(oldcontext);
    CurrentResourceOwner = oldowner;

    edata_jb = InfluxErrorDataGetJsonb(edata);

    (void)JsonbToCString(edata_text, &edata_jb->root, VARSIZE(edata_jb));

    InfluxHttpWorkerSendResponse(state,
                                 client_fd,
                                 400,
                                 "Bad Request",
                                 fields,
                                 sizeof(fields) / sizeof(*fields),
                                 edata_text->data);
    InfluxHttpWorkerDelConnection(state, client_fd);
    destroyStringInfo(edata_text);
  }
  PG_END_TRY();
}

/*
 * HTTP worker process.
 *
 * This will create a listen socket on the listen ports and process
 * all requests.
 */
void InfluxHttpWorkerMain(Datum arg) {
  struct epoll_event events[10];
  InfluxHttpWorkerState state;
  ResourceOwner resowner;

  /* Establish signal handlers; once that's done, unblock signals. */
  pqsignal(SIGTERM, SignalHandlerForShutdownRequest);
  pqsignal(SIGHUP, SignalHandlerForConfigReload);
  BackgroundWorkerUnblockSignals();

  Assert(CurrentResourceOwner == NULL);
  resowner = ResourceOwnerCreate(NULL, "TaskRunnerMain");
  CurrentResourceOwner = resowner;
  CurrentMemoryContext = AllocSetContextCreate(
      TopMemoryContext, "InfluxHttpWorker", ALLOCSET_DEFAULT_SIZES);

  elog(LOG,
       "InfluxDB HTTP Worker connecting to database %s",
       influxdb_database_name);
  BackgroundWorkerInitializeConnection(influxdb_database_name, NULL, 0);

  CurrentResourceOwner = resowner;

  pgstat_report_activity(STATE_RUNNING, "initializing worker state");

  InfluxHttpWorkerInitState(&state);

  while (!ShutdownRequestPending) {
    int nfds;

    CHECK_FOR_INTERRUPTS();

    pgstat_report_activity(STATE_IDLE, "waiting for input");

    nfds = epoll_wait(state.epoll_fd, events, 10, -1);
    if (nfds == -1)
      ereport(
          LOG, errcode_for_socket_access(), errmsg("epoll_wait failed: %m"));

    CHECK_FOR_INTERRUPTS();

    if (ConfigReloadPending) {
      ConfigReloadPending = false;
      ProcessConfigFile(PGC_SIGHUP);
    }

    for (int i = 0; i < nfds; i++) {
      int fd = events[i].data.fd;
      if (fd == state.listen_fd) {
        pgstat_report_activity(STATE_RUNNING, "accepting connection");
        InfluxHttpWorkerAcceptConnection(&state);
      } else {
        pgstat_report_activity(STATE_RUNNING, "processing data");
        InfluxHttpWorkerProcessData(&state, fd);
      }
    }
  }

  proc_exit(1);
}

void InfluxHttpWorkerInit(BackgroundWorker* worker) {
  memset(worker, 0, sizeof(*worker));

  /* Shared memory access is necessary to connect to the database. */
  worker->bgw_flags =
      BGWORKER_SHMEM_ACCESS | BGWORKER_BACKEND_DATABASE_CONNECTION;

  elog(LOG, "%s: initializing HTTP worker", __func__);

  worker->bgw_start_time = BgWorkerStart_RecoveryFinished;
  worker->bgw_restart_time = BGW_NEVER_RESTART;
  sprintf(worker->bgw_library_name, INFLUXDB_LIBRARY_NAME);
  sprintf(worker->bgw_function_name, INFLUXDB_HTTP_FUNCTION_NAME);
  snprintf(worker->bgw_name, BGW_MAXLEN, "InfluxDB HTTP protocol worker");
  snprintf(worker->bgw_type, BGW_MAXLEN, "InfluxDB HTTP protocol worker");
}
