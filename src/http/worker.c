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

#include "http/worker.h"

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
#include <utils/lsyscache.h>
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
#include "exec/insert.h"
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
  InfluxHttpRequestType type; /* Endpoint type, e.g, a write endpoint */
  Oid nspoid;                 /* Namespace OID for the "database" */
} InfluxHttpRequestData;

static void HttpWorkerInsertMeasurements(Oid nspid, const char* buf,
                                         size_t buflen) {
  pgstat_report_activity(STATE_RUNNING, "processing lines");

  process_text_internal(nspid, (char*)buf, buflen);

  pgstat_report_activity(STATE_IDLE, NULL);
}

static void handle_write_param(InfluxHttpRequestData* data, const char* key,
                               const char* val, const char* endptr) {
  const size_t keylen = (val - 1) - key;
  const size_t vallen = endptr - val;
  char name[NAMEDATALEN] = {0};

  if (strncmp(key, "db", keylen) == 0) {
    memcpy(name, val, vallen);
    data->nspoid = get_namespace_oid(name, false);
  }
}

static void parse_write_params(InfluxHttpRequestData* data, const char* start) {
  const char* key = start + 1;
  const char* val = NULL;
  const char* ptr;

  /* If it doesn't start with a '?', there are no parameters */
  if (*start != '?')
    return;

  /* From RFC 3986 3.4:
   *
   *   The query component is indicated by the first question mark
   *   ("?")  character and terminated by a number sign ("#")
   *   character or by the end of the URI.
   *
   * Here the query component will start after the question mark and
   * end with the first space (which is followed by the HTTP version).
   */
  for (ptr = start + 1; *ptr != '#' && *ptr != ' '; ++ptr) {
    if (*ptr == '=') {
      val = ptr + 1;
    } else if (*ptr == '&') {
      Assert(val != NULL && key != NULL);
      handle_write_param(data, key, val, ptr);
      key = ptr + 1; /* Start of next key */
      val = NULL;    /* The value does not exist here */
    }
  }

  /* Handle last parameter, if there were one */
  if (val)
    handle_write_param(data, key, val, ptr);
}

static int on_url(http_parser* parser, const char* at, size_t length) {
  const char write[] = "/write";
  size_t pathlen = strcspn(at, "? ");

  if (pathlen == sizeof(write) - 1 && strncmp(at, write, pathlen) == 0) {
    InfluxHttpRequestData* data = parser->data;
    data->type = OPERATION_WRITE;
    parse_write_params(data, &at[pathlen]);
    return 0; /*  All OK */
  }

  parser->status_code = 404;

  return 1; /* Error */
}

static int on_body(http_parser* parser, const char* buf, size_t len) {
  InfluxHttpRequestData* data = parser->data;
  switch (data->type) {
    case OPERATION_WRITE:
      HttpWorkerInsertMeasurements(data->nspoid, buf, len);
      return 0;
    default:
      return 1;
  }
}

static const char* InfluxHttpStatusMessage(int status_code) {
  switch (status_code) {
    case 400:
      return "Bad Request";
    case 404:
      return "Not Found";
    case 204:
      return "No Content";
    default:
      return "Unknown Status";
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
void InfluxHttpWorkerSendResponse(const InfluxHttpWorkerState* state, int fd,
                                  int status_code,
                                  const InfluxHttpHeaderData field[],
                                  size_t nfields, const char* body) {
  ssize_t sent;
  StringInfoData response;
  time_t now = time(NULL);
  char buf[128];

  Assert(content_type != NULL);

  initStringInfo(&response);
  appendStringInfo(&response,
                   "HTTP/1.1 %d %s\r\n",
                   status_code,
                   InfluxHttpStatusMessage(status_code));

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

  sent = write(fd, response.data, response.len);
  if (sent != response.len)
    ereport(LOG,
            errcode_for_socket_access(),
            errmsg("sent %ld bytes of response but should have sent %d: %m",
                   sent,
                   response.len));

  resetStringInfo(&response);
}

void InfluxHttpWorkerSendErrorResponse(InfluxHttpWorkerState* state, int fd,
                                       int status_code, Jsonb* content) {
  const InfluxHttpHeaderData fields[] = {
      {"Content-Type", "application/json"},
      {"Connection", "close"},
  };
  size_t nfields = sizeof(fields) / sizeof(*fields);
  StringInfoData text_content = {NULL};

  /*
   * Maybe we can use a scratch memory context for each request
   * instead and make cleanup easy.
   */
  if (content) {
    initStringInfo(&text_content);
    (void)JsonbToCString(&text_content, &content->root, VARSIZE(content));
  }

  InfluxHttpWorkerSendResponse(
      state, fd, status_code, fields, nfields, text_content.data);

  if (text_content.data)
    pfree(text_content.data);

  InfluxHttpWorkerDelConnection(state, fd);
}

void InfluxHttpWorkerDelConnection(InfluxHttpWorkerState* state, int fd) {
  elog(DEBUG1,
       "%s: removing file descriptor %d from epoll set %d",
       __func__,
       fd,
       state->epoll_fd);

  Assert(state->http_connection_hash != NULL);

  hash_search(state->http_connection_hash, &fd, HASH_REMOVE, NULL);

  if (epoll_ctl(state->epoll_fd, EPOLL_CTL_DEL, fd, NULL) == -1)
    ereport(ERROR,
            errcode_for_socket_access(),
            errmsg("could not remove file descriptor %d from epoll set %d: %m",
                   fd,
                   state->epoll_fd));

  shutdown(fd, SHUT_RDWR);
  close(fd);
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

/*
 * Function: InfluxHttpWorkerAddConnection
 *
 * Add a new connection to the state and set up the necessary
 * processing information.
 *
 * Parameters:
 *
 *    state - InfluxDB HTTP worker state
 *    fd - file descriptor for connection where data is read
 */
void InfluxHttpWorkerAddConnection(InfluxHttpWorkerState* state, int fd) {
  InfluxHttpConnectionEntry* entry;
  bool found;

  extend_epoll_set(state, fd);

  if (state->http_connection_hash == NULL) {
    HASHCTL ctl = {
        .keysize = sizeof(int),
        .entrysize = sizeof(InfluxHttpConnectionEntry),
    };
    state->http_connection_hash =
        hash_create("http_connections", 8, &ctl, HASH_ELEM | HASH_BLOBS);
  }

  entry = hash_search(state->http_connection_hash, &fd, HASH_ENTER, &found);
  if (found) {
    elog(WARNING, "adding connection %d a second time, not changing state", fd);
  } else {
    memset(&entry->settings, 0, sizeof(entry->settings));
    entry->settings.on_url = on_url;
    entry->settings.on_body = on_body;
    http_parser_init(&entry->parser, HTTP_REQUEST);
    entry->parser.data = palloc0(sizeof(InfluxHttpRequestData));
  }
}

/*
 * Function: InfluxHttpWorkerInitState
 *
 * Initialize the worker state.
 */
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
  state->listen_fd = InfluxNetworkListenerCreate(
      influxdb_http_service, (struct sockaddr*)&addr, &addrlen);
  if (state->listen_fd == -1)
    ereport(ERROR,
            errcode_for_socket_access(),
            errmsg("could not create socket: %m"));

  extend_epoll_set(state, state->listen_fd);

  elog(LOG, "InfluxDB HTTP Worker listening on port %d", addr.sin_port);
}

InfluxHttpConnectionEntry* InfluxHttpWorkerGetConnection(
    InfluxHttpWorkerState* state, int fd) {
  if (state->http_connection_hash == NULL)
    return NULL;
  else
    return hash_search(state->http_connection_hash, &fd, HASH_FIND, NULL);
}

void InfluxHttpWorkerAcceptConnection(InfluxHttpWorkerState* state) {
  pgstat_report_activity(STATE_RUNNING, "accepting connections");
  while (1) {
    struct sockaddr_in addr;
    socklen_t addrlen = sizeof(addr);
    int fd;
    char addr_text[INET_ADDRSTRLEN];

    fd = accept(state->listen_fd, (struct sockaddr*)&addr, &addrlen);
    if (fd == -1) {
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        break;
      } else {
        ereport(LOG,
                errcode_for_socket_access(),
                errmsg("failed to accept connection: %m"));
        continue;
      }
    }

    inet_ntop(AF_INET, &addr.sin_addr, addr_text, sizeof(addr_text));
    elog(LOG, "accepted connection from %s", addr_text);

    if (InfluxNetworkSetNonblocking(fd) == -1) {
      ereport(LOG,
              errcode_for_socket_access(),
              errmsg("failed to set socket to non-blocking: %m"));
      close(fd);
      continue;
    }

    InfluxHttpWorkerAddConnection(state, fd);
  }
}

/*
 * Function: InfluxdbHttpWorkerProcessData
 *
 * Process received data by feeding it into the associated parser.
 *
 * Processing data proceeds by reading data from the client file
 * descriptor and appending it to the client part of the state.
 *
 * Once no more data is received, the request is parsed and processed.
 *
 * If the parser fails, it will send an error message back, shut down
 * the parser, and close the connection.
 */
void InfluxHttpWorkerProcessData(InfluxHttpWorkerState* state, int fd) {
  MemoryContext oldcontext = CurrentMemoryContext;
  ResourceOwner oldowner = CurrentResourceOwner;
  int err;

  pgstat_report_activity(STATE_RUNNING, "processing data");

  PG_TRY();
  {
    StringInfoData request;
    InfluxHttpConnectionEntry* entry;
    ssize_t parsed, len;
    char buffer[BUFFER_SIZE] = {0};
    InfluxHttpHeaderData fields[] = {
        {"Connection", "close"},
    };

    initStringInfo(&request);

    /* Read data info a buffer */
    while (1) {
      /* Not a datagram channel so recv and read are equivalent */
      len = read(fd, buffer, BUFFER_SIZE);

      elog(DEBUG1, "received %ld bytes on %d:\n%s", len, fd, buffer);

      /* If connection is shut down, we do not need to send a response. */
      if (len == 0)
        return;
      /* If read data into the buffer, append it to the data to be read */
      else if (len > 0)
        appendBinaryStringInfo(&request, buffer, len);
      /* If there are no more data, we start processing data */
      else if (len == -1 && (errno == EAGAIN || errno == EWOULDBLOCK))
        break;
      /* If we had an error, send a respose and close connection */
      else if (len == -1)
        ereport(
            ERROR, errcode_for_socket_access(), errmsg("recv call failed: %m"));
    }

    /* Once all data is read, we process it it and send a response. */

    entry = InfluxHttpWorkerGetConnection(state, fd);
    if (entry == NULL) {
      elog(LOG, "entry for file descriptor %d not found", fd);
      break;
    }

    SetCurrentStatementStartTimestamp();
    StartTransactionCommand();

    if ((err = SPI_connect()) != SPI_OK_CONNECT)
      elog(ERROR, "SPI_connect failed: %s", SPI_result_code_string(err));

    PushActiveSnapshot(GetTransactionSnapshot());

    parsed = http_parser_execute(
        &entry->parser, &entry->settings, request.data, request.len);

    /* We don't need the SPI any more */
    if ((err = SPI_finish()) != SPI_OK_FINISH)
      elog(ERROR, "SPI_finish failed: %s", SPI_result_code_string(err));

    PopActiveSnapshot();
    CommitTransactionCommand();

    elog(DEBUG1,
         "parsed %ld bytes of %d, status_code: %d",
         parsed,
         request.len,
         entry->parser.status_code);

    if (entry->parser.status_code > 0) {
      JsonbParseState* jbstate = NULL;
      JsonbValue* result;

      (void)pushJsonbValue(&jbstate, WJB_BEGIN_OBJECT, NULL);

      InfluxJsonbAddKeyValue(&jbstate, "error", "endpoint does not exist");

      result = pushJsonbValue(&jbstate, WJB_END_OBJECT, NULL);

      InfluxHttpWorkerSendErrorResponse(
          state, fd, entry->parser.status_code, JsonbValueToJsonb(result));
    } else if (parsed != request.len) {
      JsonbParseState* jbstate = NULL;
      JsonbValue* result;

      (void)pushJsonbValue(&jbstate, WJB_BEGIN_OBJECT, NULL);

      InfluxJsonbAddKeyValue(
          &jbstate,
          "error",
          http_errno_name(HTTP_PARSER_ERRNO(&entry->parser)));
      InfluxJsonbAddKeyValue(
          &jbstate,
          "detail",
          http_errno_description(HTTP_PARSER_ERRNO(&entry->parser)));

      result = pushJsonbValue(&jbstate, WJB_END_OBJECT, NULL);

      InfluxHttpWorkerSendErrorResponse(
          state, fd, 400, JsonbValueToJsonb(result));
    } else {
      InfluxHttpWorkerSendResponse(
          state, fd, 204, fields, sizeof(fields) / sizeof(*fields), NULL);
      InfluxHttpWorkerDelConnection(state, fd);
    }
  }
  PG_CATCH();
  {
    ErrorData* edata;
    Jsonb* edata_jb;

    MemoryContextSwitchTo(oldcontext);

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
    InfluxHttpWorkerSendErrorResponse(state, fd, 400, edata_jb);
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

  elog(
      LOG, "InfluxDB HTTP Worker connecting to database %s", influxdb_database);
  BackgroundWorkerInitializeConnection(influxdb_database, NULL, 0);

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
      if (fd == state.listen_fd)
        InfluxHttpWorkerAcceptConnection(&state);
      else
        InfluxHttpWorkerProcessData(&state, fd);
    }

    /*
     * We have a single resource owner for all connection, which
     * works, but we should probably have a resource owner for each
     * connection.
     */
    CurrentResourceOwner = resowner;
  }

  /*
   * Exiting with exit code 0 since this is a proper shutdown and should not
   * trigger a restart.
   */
  proc_exit(0);
}

void InfluxHttpWorkerInit(BackgroundWorker* worker) {
  memset(worker, 0, sizeof(*worker));

  /* Shared memory access is necessary to connect to the database. */
  worker->bgw_flags =
      BGWORKER_SHMEM_ACCESS | BGWORKER_BACKEND_DATABASE_CONNECTION;

  elog(DEBUG1, "%s: initializing HTTP worker", __func__);

  worker->bgw_start_time = BgWorkerStart_RecoveryFinished;
  sprintf(worker->bgw_library_name, INFLUXDB_LIBRARY_NAME);
  sprintf(worker->bgw_function_name, INFLUXDB_HTTP_FUNCTION_NAME);
  snprintf(worker->bgw_name, BGW_MAXLEN, "InfluxDB HTTP protocol worker");
  snprintf(worker->bgw_type, BGW_MAXLEN, "InfluxDB HTTP protocol worker");

  if (influxdb_http_worker_restart_time > 0)
    worker->bgw_restart_time = influxdb_http_worker_restart_time;
  else
    worker->bgw_restart_time = BGW_NEVER_RESTART;
}
