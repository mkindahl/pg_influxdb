#include <c.h>
#include <fmgr.h>
#include <funcapi.h>
#include <miscadmin.h>
#include <postgres.h>

#include "parser.h"
#include "utils.h"

#include <access/table.h>
#include <access/tupdesc.h>
#include <executor/spi.h>
#include <storage/lockdefs.h>
#include <utils/builtins.h>
#include <utils/guc.h>
#include <utils/jsonb.h>
#include <utils/lsyscache.h>
#include <utils/palloc.h>
#include <utils/rel.h>

PG_MODULE_MAGIC;

void _PG_init(void);

PG_FUNCTION_INFO_V1(process_line);

bool influxdb_keep_quotes = false;

static HTAB* influxdb_plan_cache = NULL;

typedef struct InfluxRelationCacheEntry {
  Oid relid;
  SPIPlanPtr plan;
} InfluxRelationCacheEntry;

static bool is_time_type(Oid typid) {
  switch (typid) {
    case TIMESTAMPOID:
    case TIMESTAMPTZOID:
    case DATEOID:
    case INTERVALOID:
    case TIMEOID:
    case TIMETZOID:
      return true;
    default:
      return false;
  }
}

static SPIPlanPtr InfluxGetPlanFor(Relation relation) {
  Oid relid = RelationGetRelid(relation);
  AttInMetadata* attinmeta =
      TupleDescGetAttInMetadata(RelationGetDescr(relation));
  InfluxRelationCacheEntry* entry;
  bool found;

  if (!influxdb_plan_cache) {
    HASHCTL ctl;
    ctl.keysize = sizeof(Oid);
    ctl.entrysize = sizeof(InfluxRelationCacheEntry);
    influxdb_plan_cache = hash_create("InfluxDB Relation Plan Cache", 32, &ctl,
                                      HASH_ELEM | HASH_BLOBS);
  }

  entry = hash_search(influxdb_plan_cache, &relid, HASH_ENTER, &found);

  if (!found) {
    TupleDesc tupdesc = attinmeta->tupdesc;
    Oid* argtypes = palloc_array(Oid, tupdesc->natts);
    SPIPlanPtr plan;
    StringInfoData stmt;

    initStringInfo(&stmt);

    /* Create insert statement for relation */
    appendStringInfo(&stmt, "INSERT INTO %s.%s VALUES (",
                     quote_identifier(SPI_getnspname(relation)),
                     quote_identifier(SPI_getrelname(relation)));
    for (int i = 0; i < tupdesc->natts; ++i) {
      argtypes[i] = SPI_gettypeid(tupdesc, i + 1);
      elog(DEBUG1, "argtypes[%d]: %d (type \"%s\")", i, argtypes[i],
           SPI_gettype(tupdesc, i + 1));
      appendStringInfo(&stmt, "$%d", i + 1);
      if (i < tupdesc->natts - 1)
        appendStringInfoString(&stmt, ", ");
    }
    appendStringInfoString(&stmt, ")");

    plan = SPI_prepare(stmt.data, tupdesc->natts, argtypes);

    if (!plan)
      elog(ERROR, "SPI_prepare failed for relation %s: %s",
           SPI_getrelname(relation), SPI_result_code_string(SPI_result));

    if (SPI_keepplan(plan))
      elog(ERROR, "SPI_keepplan failed for relation %s",
           SPI_getrelname(relation));

    entry->relid = relid;
    entry->plan = plan;
  }

  return entry->plan;
}

/*
 * Remove pairs from the list with a matching key in the tuple
 * descriptor and add the value to the datum list.
 *
 * This will parse the string value of the value with the input
 * function for the type. If the parsing fails for any reason, the
 * field is not added to the datum array and will stay in the list.
 *
 * If the datum value has already been filled in (checked by checking
 * cnulls), we also do not remove the pair. This means that conflicts
 * in keys between fields and tags will keep fields in the _fields
 * column.
 */
static List* InfluxFillAndRemovePairs(List* pairs, AttInMetadata* attinmeta,
                                      Datum* values, char* cnulls) {
  ListCell* cell;
  TupleDesc tupdesc = attinmeta->tupdesc;
  List* new_pairs = pairs;
  ErrorSaveContext escontext = {T_ErrorSaveContext};

  foreach (cell, pairs) {
    InfluxPair* pair = lfirst(cell);
    StringInfo key = InfluxTokenGetString(&pair->key);
    int attnum = SPI_fnumber(tupdesc, key->data);
    elog(DEBUG1, "key: %s, attnum: %d, cnull: '%c'", key->data, attnum,
         attnum > 0 ? cnulls[attnum - 1] : '*');
    if (attnum > 0 && cnulls[attnum - 1] == 'n') {
      FmgrInfo* flinfo = &attinmeta->attinfuncs[attnum - 1];
      StringInfo value = InfluxTokenGetString(&pair->val);
      elog(DEBUG1, "value: %s, cnull: '%c'", value->data, cnulls[attnum - 1]);
      if (InputFunctionCallSafe(flinfo, value->data,
                                attinmeta->attioparams[attnum - 1],
                                attinmeta->atttypmods[attnum - 1],
                                (Node*)&escontext, &values[attnum - 1])) {
        cnulls[attnum - 1] = ' ';
        new_pairs = foreach_delete_current(new_pairs, cell);
      }
    }
  }
  return new_pairs;
}

/*
 * Fill datum arrays with information from the data point.
 *
 * This will fetch the table and figure out where to store the
 * information based on the names of the fields and tags.
 *
 * The table is already figured out based on the measurement name.
 *
 * The following column names are reserved and used (in general, avoid
 * column names starting with an underscore):
 *
 * _time: timestamp of the measurement.
 * _tags: JSON containing the tags of the measurement
 * _fields: JSON containing the fields of the measurement
 *
 * In many cases we just ignore the measurement if it is not the
 * correct format to avoid flooding the log with error messages.
 *
 * This will modify the data point structure, so do not use it
 * afterwards.
 */
static bool InfluxFillValues(InfluxDataPoint* data_point, TupleDesc tupdesc,
                             Datum* values, char* cnulls, bool raise_error) {
  AttInMetadata* attinmeta = TupleDescGetAttInMetadata(tupdesc);
  int64 timestamp;
  int time_attnum, tags_attnum, fields_attnum;
  char* endptr;

  memset(cnulls, 'n', tupdesc->natts);

  elog(DEBUG1, "filling datums for data point %s",
       DatumGetCString(DirectFunctionCall1(
           jsonb_out, JsonbPGetDatum(DataPointGetJsonB(data_point)))));

  time_attnum = SPI_fnumber(tupdesc, "_time");
  if (time_attnum > 0) {
    /* If this is not a time type, we ignore it */
    if (!is_time_type(SPI_gettypeid(tupdesc, time_attnum))) {
      elog(DEBUG1, "no _time column: ignoring data point %s",
           DatumGetCString(DirectFunctionCall1(
               jsonb_out, JsonbPGetDatum(DataPointGetJsonB(data_point)))));
      return false;
    }

    errno = 0;
    timestamp = strtou64(data_point->timestamp.buf, &endptr, 0);

    if ((errno && errno != ERANGE) || endptr == data_point->timestamp.buf) {
      if (raise_error)
        ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                        errmsg("invalid input syntax for: \"%s\"",
                               data_point->timestamp.buf)));
      else
        return false;
    }

    if (errno == ERANGE) {
      if (raise_error)
        ereport(ERROR, errcode(ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE),
                errmsg("value \"%s\" is out of range for timestamp",
                       data_point->timestamp.buf));
      else
        return false;
    }

    /* PostgreSQL timestamp are in microseconds since PostgreSQL epoch
     */
    timestamp /= 1000;
    timestamp -= USECS_PER_SEC *
                 ((POSTGRES_EPOCH_JDATE - UNIX_EPOCH_JDATE) * SECS_PER_DAY);

    values[time_attnum - 1] = Int64GetDatum(timestamp);
    cnulls[time_attnum - 1] = ' ';
  }

  InfluxFillAndRemovePairs(data_point->tags, attinmeta, values, cnulls);
  InfluxFillAndRemovePairs(data_point->fields, attinmeta, values, cnulls);

  tags_attnum = SPI_fnumber(tupdesc, "_tags");
  if (tags_attnum > 0) {
    if (SPI_gettypeid(tupdesc, tags_attnum) != JSONBOID) {
      elog(DEBUG1, "_tags column is not jsonb: ignoring data point %s",
           DatumGetCString(DirectFunctionCall1(
               jsonb_out, JsonbPGetDatum(DataPointGetJsonB(data_point)))));
      return false;
    }
    values[tags_attnum - 1] =
        JsonbPGetDatum(InfluxBuildJsonObject(data_point->tags));
    cnulls[tags_attnum - 1] = ' ';
  }

  fields_attnum = SPI_fnumber(tupdesc, "_fields");
  if (fields_attnum > 0) {
    if (SPI_gettypeid(tupdesc, tags_attnum) != JSONBOID) {
      elog(DEBUG1, "_tags column is not jsonb: ignoring data point %s",
           DatumGetCString(DirectFunctionCall1(
               jsonb_out, JsonbPGetDatum(DataPointGetJsonB(data_point)))));
      return false;
    }
    values[fields_attnum - 1] =
        JsonbPGetDatum(InfluxBuildJsonObject(data_point->fields));
    cnulls[fields_attnum - 1] = ' ';
  }

  return true;
}

/*
 * Process a data point.
 */
static void InfluxProcessDataPoint(Oid nspid, InfluxDataPoint* data_point,
                                   bool raise_error) {
  char* cnulls;
  Oid relid;
  StringInfo measurement;
  int err, natts;
  Relation relation;
  Datum* values;
  TupleDesc tupdesc;

  measurement = InfluxTokenGetString(&data_point->measurement);

  /*
   * Get the relation id of the measurement name. If none exists, we
   * silently ignore it to avoid flooding the log with error messages.
   */
  relid = get_relname_relid(measurement->data, nspid);
  if (relid == InvalidOid) {
    if (raise_error)
      ereport(ERROR, errmsg("no relation \"%s\" found in namespace \"%s\"",
                            measurement->data, get_namespace_name(nspid)));

    return;
  }

  relation = table_open(relid, RowExclusiveLock);
  tupdesc = RelationGetDescr(relation);
  natts = tupdesc->natts;
  values = palloc0_array(Datum, natts);
  cnulls = palloc_array(char, natts);

  elog(DEBUG1, "opened table %s with %d attributes",
       RelationGetRelationName(relation), natts);
  if (InfluxFillValues(data_point, tupdesc, values, cnulls, raise_error)) {
    SPIPlanPtr plan = InfluxGetPlanFor(relation);

    err = SPI_execute_plan(plan, values, cnulls, false, 0);
    if (err != SPI_OK_INSERT)
      elog(LOG, "SPI_execute_plan failed executing: %s",
           SPI_result_code_string(err));
  }

  table_close(relation, NoLock);
}

Datum process_line(PG_FUNCTION_ARGS) {
  Oid nspid = PG_GETARG_OID(0);
  text* input = PG_GETARG_TEXT_PP(1);
  InfluxParseState state;
  InfluxDataPoint data_point;
  int err;

  InfluxParseStateInit(&state, &data_point, VARDATA_ANY(input),
                       VARSIZE_ANY_EXHDR(input));
  InfluxParseDataPoint(&state);

  if ((err = SPI_connect()) != SPI_OK_CONNECT)
    elog(ERROR, "SPI_connect failed: %s", SPI_result_code_string(err));

  InfluxProcessDataPoint(nspid, &data_point, true);

  if ((err = SPI_finish()) != SPI_OK_FINISH)
    elog(ERROR, "SPI_finish failed: %s", SPI_result_code_string(err));

  InfluxParseStateFinish(&state);
  PG_RETURN_VOID();
}

void _PG_init(void) {
  /* We use PGC_USERSET to be able to debug this. It could be PGC_SIGHUP. */
  DefineCustomBoolVariable(
      "influxdb.keep_quotes",
      "Keep quotes as part of the string for quoted strings.", NULL,
      &influxdb_keep_quotes, false, PGC_USERSET, 0, NULL, NULL, NULL);

  if (!process_shared_preload_libraries_in_progress)
    return;

  MarkGUCPrefixReserved("influxdb");
}
