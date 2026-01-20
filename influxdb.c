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
#include "http_worker.h"
#include "insert.h"
#include "parser.h"

PG_MODULE_MAGIC;

void _PG_init(void);

PG_FUNCTION_INFO_V1(process_text);

bool influxdb_keep_quotes = false;
bool influxdb_auto_create_table = false;
char* influxdb_http_service = INFLUXDB_DEFAULT_HTTP_SERVICE;
char* influxdb_database = NULL;
char* influxdb_schema_name = INFLUXDB_DEFAULT_SCHEMA_NAME;
int influxdb_http_workers = 4;

void process_text_internal(Oid nspid, char* buf, size_t len) {
  InfluxParseState state;

  InfluxParseStateInit(&state, buf, len);

  while (InfluxParseStateHasMore(&state)) {
    InfluxDataPoint data_point;
    InfluxParseDataPoint(&state, &data_point);
    InfluxInsertDataPoint(nspid, &data_point, true);
  }

  InfluxParseStateFinish(&state);
}

Datum process_text(PG_FUNCTION_ARGS) {
  Oid nspid = PG_GETARG_OID(0);
  text* input = PG_GETARG_TEXT_PP(1);
  int err;

  if ((err = SPI_connect()) != SPI_OK_CONNECT)
    elog(ERROR, "SPI_connect failed: %s", SPI_result_code_string(err));

  PushActiveSnapshot(GetTransactionSnapshot());

  process_text_internal(nspid, VARDATA_ANY(input), VARSIZE_ANY_EXHDR(input));

  if ((err = SPI_finish()) != SPI_OK_FINISH)
    elog(ERROR, "SPI_finish failed: %s", SPI_result_code_string(err));

  PopActiveSnapshot();

  PG_RETURN_VOID();
}

void _PG_init(void) {
  BackgroundWorker worker;

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
      "Service name or port number to listen for HTTP connections. If it is a "
      "service name, it will be looked up.",
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

  DefineCustomStringVariable("influxdb.schema_name",
                             "Schema name for measurement tables.",
                             "Schema name for all tables with measurements.",
                             &influxdb_schema_name,
                             INFLUXDB_DEFAULT_SCHEMA_NAME, /* boot value */
                             PGC_POSTMASTER,               /* option context */
                             0,                            /* option flags */
                             NULL,                         /* check hook */
                             NULL,                         /* assign hook */
                             NULL);                        /* show hook */

  MarkGUCPrefixReserved("influxdb");

  InfluxHttpWorkerInit(&worker);
  for (int i = 0; i < influxdb_http_workers; i++)
    RegisterBackgroundWorker(&worker);
}
