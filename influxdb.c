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

#include "parser.h"
#include "plans.h"
#include "utils.h"

PG_MODULE_MAGIC;

void _PG_init(void);

PG_FUNCTION_INFO_V1(process_line);

bool influxdb_keep_quotes = false;
bool influxdb_auto_create_table = false;

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

static Oid InfluxCreateTable(Oid nspid, InfluxDataPoint* data_point,
                             bool raise_error) {
  CreateStmt* create = makeNode(CreateStmt);
  ObjectAddress address;

  create->relation =
      makeRangeVar(get_namespace_name(nspid),
                   InfluxTokenGetString(&data_point->measurement)->data,
                   -1);
  create->tableElts =
      list_make3(makeColumnDef("_time", TIMESTAMPTZOID, -1, InvalidOid),
                 makeColumnDef("_tags", JSONBOID, -1, InvalidOid),
                 makeColumnDef("_fields", JSONBOID, -1, InvalidOid));
  address = DefineRelation(create, RELKIND_RELATION, GetUserId(), NULL, NULL);
  return address.objectId;
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
    if (attnum > 0 && cnulls[attnum - 1] == 'n') {
      FmgrInfo* flinfo = &attinmeta->attinfuncs[attnum - 1];
      StringInfo value = InfluxTokenGetString(&pair->val);
      if (InputFunctionCallSafe(flinfo,
                                value->data,
                                attinmeta->attioparams[attnum - 1],
                                attinmeta->atttypmods[attnum - 1],
                                (Node*)&escontext,
                                &values[attnum - 1])) {
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

  time_attnum = SPI_fnumber(tupdesc, "_time");
  if (time_attnum > 0) {
    /* If this is not a time type, we ignore it */
    if (!is_time_type(SPI_gettypeid(tupdesc, time_attnum)))
      return false;

    errno = 0;
    timestamp = strtou64(data_point->timestamp.buf, &endptr, 0);

    if ((errno && errno != ERANGE) || endptr == data_point->timestamp.buf) {
      if (raise_error)
        ereport(ERROR,
                (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                 errmsg("invalid input syntax for: \"%s\"",
                        data_point->timestamp.buf)));
      else
        return false;
    }

    if (errno == ERANGE) {
      if (raise_error)
        ereport(ERROR,
                errcode(ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE),
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
    if (SPI_gettypeid(tupdesc, tags_attnum) != JSONBOID)
      return false;
    values[tags_attnum - 1] =
        JsonbPGetDatum(InfluxBuildJsonObject(data_point->tags));
    cnulls[tags_attnum - 1] = ' ';
  }

  fields_attnum = SPI_fnumber(tupdesc, "_fields");
  if (fields_attnum > 0) {
    if (SPI_gettypeid(tupdesc, tags_attnum) != JSONBOID)
      return false;
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
   * Get the relation id of the measurement name.
   *
   * If none exists, we try to create a table for it if
   * auto_create_table is true.
   *
   * Otherwise we silently ignore it to avoid flooding the log with
   * error messages.
   */
  relid = get_relname_relid(measurement->data, nspid);
  if (relid == InvalidOid) {
    if (influxdb_auto_create_table) {
      relid = InfluxCreateTable(nspid, data_point, raise_error);
    } else if (raise_error)
      ereport(ERROR,
              errmsg("no relation \"%s\" found in namespace \"%s\"",
                     measurement->data,
                     get_namespace_name(nspid)));
    else
      return;
  }

  relation = table_open(relid, RowExclusiveLock);
  tupdesc = RelationGetDescr(relation);
  natts = tupdesc->natts;
  values = palloc0_array(Datum, natts);
  cnulls = palloc_array(char, natts);

  if (InfluxFillValues(data_point, tupdesc, values, cnulls, raise_error)) {
    SPIPlanPtr plan = InfluxGetPlanFor(relation);

    err = SPI_execute_plan(plan, values, cnulls, false, 0);
    if (err != SPI_OK_INSERT)
      elog(LOG,
           "SPI_execute_plan failed executing: %s",
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

  if ((err = SPI_connect()) != SPI_OK_CONNECT)
    elog(ERROR, "SPI_connect failed: %s", SPI_result_code_string(err));

  InfluxParseStateInit(
      &state, &data_point, VARDATA_ANY(input), VARSIZE_ANY_EXHDR(input));
  InfluxParseDataPoint(&state);
  InfluxProcessDataPoint(nspid, &data_point, true);
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
