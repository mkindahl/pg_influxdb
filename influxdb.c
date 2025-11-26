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
#include <storage/lockdefs.h>
#include <utils/builtins.h>
#include <utils/guc.h>
#include <utils/jsonb.h>
#include <utils/lsyscache.h>
#include <utils/palloc.h>
#include <utils/rel.h>

#include "insert.h"
#include "parser.h"

PG_MODULE_MAGIC;

void _PG_init(void);

PG_FUNCTION_INFO_V1(process_line);

bool influxdb_keep_quotes = false;
bool influxdb_auto_create_table = false;

Datum process_line(PG_FUNCTION_ARGS) {
  Oid nspid = PG_GETARG_OID(0);
  text* input = PG_GETARG_TEXT_PP(1);
  InfluxParseState state;
  InfluxDataPoint data_point;
  int err;

  if ((err = SPI_connect()) != SPI_OK_CONNECT)
    elog(ERROR, "SPI_connect failed: %s", SPI_result_code_string(err));

  InfluxParseStateInit(
      &state, &data_point, VARDATA_ANY(input), VARSIZE_ANY_EXHDR(input));
  InfluxParseDataPoint(&state);
  InfluxInsertDataPoint(nspid, &data_point, true);
  InfluxParseStateFinish(&state);

  if ((err = SPI_finish()) != SPI_OK_FINISH)
    elog(ERROR, "SPI_finish failed: %s", SPI_result_code_string(err));

  PG_RETURN_VOID();
}

void _PG_init(void) {
  /* We use PGC_USERSET to be able to debug this. It could be PGC_SIGHUP. */
  DefineCustomBoolVariable(
      "influxdb.keep_quotes",
      "Keep quotes as part of the string for quoted strings.",
      NULL,
      &influxdb_keep_quotes,
      false,
      PGC_USERSET,
      0,
      NULL,
      NULL,
      NULL);

  DefineCustomBoolVariable("influxdb.auto_create_table",
                           "Automatically create a table if metric is missing.",
                           NULL,
                           &influxdb_auto_create_table,
                           false,
                           PGC_USERSET,
                           0,
                           NULL,
                           NULL,
                           NULL);

  if (!process_shared_preload_libraries_in_progress)
    return;

  MarkGUCPrefixReserved("influxdb");
}
