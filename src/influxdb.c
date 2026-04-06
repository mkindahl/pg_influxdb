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

#include "influxdb.h"

#include <postgres.h>
#include <fmgr.h>

#include <access/table.h>
#include <access/tupdesc.h>
#include <c.h>
#include <commands/tablecmds.h>
#include <executor/spi.h>
#include <funcapi.h>
#include <miscadmin.h>
#include <nodes/makefuncs.h>
#include <postmaster/bgworker.h>
#include <storage/lockdefs.h>
#include <utils/builtins.h>
#include <utils/guc.h>
#include <utils/jsonb.h>
#include <utils/lsyscache.h>
#include <utils/palloc.h>
#include <utils/rel.h>

#include "config.h"
#include "http/worker.h"
#include "udp/worker.h"

PG_MODULE_MAGIC;

void _PG_init(void);

bool influxdb_keep_quotes = false;
bool influxdb_auto_create_table = false;
char* influxdb_http_service = INFLUXDB_DEFAULT_HTTP_SERVICE;
char* influxdb_database = NULL;
int influxdb_http_workers = 4;
int influxdb_http_worker_restart_time = INFLUXDB_DEFAULT_HTTP_RESTART_TIME;
bool influxdb_http_auth = false;

char* influxdb_udp_service = INFLUXDB_DEFAULT_UDP_SERVICE;
char* influxdb_udp_schema = INFLUXDB_DEFAULT_SCHEMA_NAME;
int influxdb_udp_read_buffer = INFLUXDB_DEFAULT_UDP_READ_BUFFER;
int influxdb_udp_workers = INFLUXDB_DEFAULT_UDP_WORKERS;

void _PG_init(void) {
  BackgroundWorker worker, udp_worker;

  /* We use PGC_USERSET to be able to debug this. It could be PGC_SIGHUP. */
  DefineCustomBoolVariable(
      "influxdb.keep_quotes",
      "Keep quotes as part of strings.",
      "Keep quotes as part of the string for quoted strings.",
      &influxdb_keep_quotes,
      false,       /* boot value */
      PGC_USERSET, /* option context */
      0,           /* option flags */
      NULL,        /* check hook */
      NULL,        /* assign hook */
      NULL);       /* show hook */

  DefineCustomBoolVariable(
      "influxdb.auto_create_table",
      "Automatically create tables for measurements.",
      "Automatically create missing tables for measurements.",
      &influxdb_auto_create_table,
      false,       /* boot value */
      PGC_USERSET, /* option context */
      0,           /* option flags */
      NULL,        /* check hook */
      NULL,        /* assign hook */
      NULL);       /* show hook */

  DefineCustomIntVariable(
      "influxdb.http_workers",
      "Number of HTTP workers.",
      "Number of HTTP workers to spawn when starting up the server.",
      &influxdb_http_workers,
      4,          /* boot value */
      0,          /* min value */
      20,         /* max value */
      PGC_SIGHUP, /* option context */
      0,          /* option flags */
      NULL,       /* check hook */
      NULL,       /* assign hook */
      NULL);      /* show hook */

  if (!process_shared_preload_libraries_in_progress)
    return;

  DefineCustomStringVariable(
      "influxdb.http_service",
      "Service name or port for HTTP connections.",
      "Service name or port number to listen for HTTP connections. If it is a"
      "service name, it will be looked up. Defaults to 8086. ",
      &influxdb_http_service,
      INFLUXDB_DEFAULT_HTTP_SERVICE, /* boot value */
      PGC_POSTMASTER,                /* option context */
      0,                             /* option flags */
      NULL,                          /* check hook */
      NULL,                          /* assign hook */
      NULL);                         /* show hook */

  /*
   * We can only write to a single database for each cluster since we
   * cannot know what database to connect to without parsing the query.
   */
  DefineCustomStringVariable("influxdb.database",
                             "Database name for all workers.",
                             "Database name for which workers will be created.",
                             &influxdb_database,
                             NULL,           /* boot value */
                             PGC_POSTMASTER, /* option context */
                             0,              /* option flags */
                             NULL,           /* check hook */
                             NULL,           /* assign hook */
                             NULL);          /* show hook */

  DefineCustomIntVariable(
      "influxdb.http_worker_restart_time",
      "Restart time for HTTP worker.",
      "If the worker exits with an error, it will restart "
      "after these many seconds. Providing 0 means never restart.",
      &influxdb_http_worker_restart_time,
      INFLUXDB_DEFAULT_HTTP_RESTART_TIME, /* boot value */
      -1,                                 /* min value */
      32600,                              /* max value */
      PGC_POSTMASTER,                     /* option context */
      0,                                  /* option flags */
      NULL,                               /* check hook */
      NULL,                               /* assign hook */
      NULL);                              /* show hook */

  DefineCustomBoolVariable(
      "influxdb.http_auth",
      "Enable HTTP Basic Auth using PostgreSQL roles.",
      "When enabled, HTTP requests must provide credentials that match "
      "a PostgreSQL role in pg_authid. Credentials can be provided via "
      "the Authorization header or u=/p= query parameters.",
      &influxdb_http_auth,
      false,          /* boot value */
      PGC_POSTMASTER, /* option context */
      0,              /* option flags */
      NULL,           /* check hook */
      NULL,           /* assign hook */
      NULL);          /* show hook */

  DefineCustomStringVariable(
      "influxdb.udp_service",
      "Service name or port for UDP connections.",
      "Service name or port number to listen for UDP connections. "
      "Defaults to 8089.",
      &influxdb_udp_service,
      INFLUXDB_DEFAULT_UDP_SERVICE, /* boot value */
      PGC_POSTMASTER,               /* option context */
      0,                            /* option flags */
      NULL,                         /* check hook */
      NULL,                         /* assign hook */
      NULL);                        /* show hook */

  DefineCustomStringVariable(
      "influxdb.udp_schema",
      "Target schema for UDP writes.",
      "Schema name used for UDP writes since UDP has no query parameters "
      "to specify the target database.",
      &influxdb_udp_schema,
      INFLUXDB_DEFAULT_SCHEMA_NAME, /* boot value */
      PGC_POSTMASTER,               /* option context */
      0,                            /* option flags */
      NULL,                         /* check hook */
      NULL,                         /* assign hook */
      NULL);                        /* show hook */

  DefineCustomIntVariable(
      "influxdb.udp_read_buffer",
      "UDP socket receive buffer size.",
      "SO_RCVBUF size for the UDP socket. 0 means use the OS default.",
      &influxdb_udp_read_buffer,
      INFLUXDB_DEFAULT_UDP_READ_BUFFER, /* boot value */
      0,                                /* min value */
      64 * 1024,                        /* max value (64 MB) */
      PGC_POSTMASTER,                   /* option context */
      GUC_UNIT_KB,                      /* option flags */
      NULL,                             /* check hook */
      NULL,                             /* assign hook */
      NULL);                            /* show hook */

  DefineCustomIntVariable(
      "influxdb.udp_workers",
      "Number of UDP workers.",
      "Number of UDP workers to spawn. Each gets its own socket via "
      "SO_REUSEPORT for kernel load balancing.",
      &influxdb_udp_workers,
      INFLUXDB_DEFAULT_UDP_WORKERS, /* boot value */
      0,                            /* min value */
      20,                           /* max value */
      PGC_POSTMASTER,               /* option context */
      0,                            /* option flags */
      NULL,                         /* check hook */
      NULL,                         /* assign hook */
      NULL);                        /* show hook */

  MarkGUCPrefixReserved("influxdb");

  InfluxHttpWorkerInit(&worker);
  for (int i = 0; i < influxdb_http_workers; i++)
    RegisterBackgroundWorker(&worker);

  InfluxUdpWorkerInit(&udp_worker);
  for (int i = 0; i < influxdb_udp_workers; i++)
    RegisterBackgroundWorker(&udp_worker);
}
