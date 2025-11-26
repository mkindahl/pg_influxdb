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

#include "plans.h"

#include <postgres.h>

#include <utils/builtins.h>
#include <utils/inval.h>
#include <utils/lsyscache.h>

static HTAB* influxdb_plan_cache = NULL;

static void InfluxInvalidatePlan(Datum arg, Oid relid) {
  bool found;
  InfluxPlanCacheEntry* entry;

  if (influxdb_plan_cache) {
    entry = hash_search(influxdb_plan_cache, &relid, HASH_REMOVE, &found);

    if (found)
      SPI_freeplan(entry->plan);
  }
}

/*
 * Create plan for a relation.
 */
static void InfluxCreatePlan(InfluxPlanCacheEntry* entry, Relation relation) {
  TupleDesc tupdesc = RelationGetDescr(relation);
  Oid* argtypes = palloc_array(Oid, tupdesc->natts);
  SPIPlanPtr plan;
  StringInfoData stmt;

  initStringInfo(&stmt);

  /* Create insert statement for relation */
  appendStringInfo(&stmt,
                   "INSERT INTO %s.%s VALUES (",
                   quote_identifier(SPI_getnspname(relation)),
                   quote_identifier(SPI_getrelname(relation)));
  for (int i = 0; i < tupdesc->natts; ++i) {
    argtypes[i] = SPI_gettypeid(tupdesc, i + 1);
    appendStringInfo(&stmt, "$%d", i + 1);
    if (i < tupdesc->natts - 1)
      appendStringInfoString(&stmt, ", ");
  }
  appendStringInfoString(&stmt, ")");

  plan = SPI_prepare(stmt.data, tupdesc->natts, argtypes);

  if (!plan)
    elog(ERROR,
         "SPI_prepare failed for relation %s: %s",
         SPI_getrelname(relation),
         SPI_result_code_string(SPI_result));

  if (SPI_keepplan(plan))
    elog(
        ERROR, "SPI_keepplan failed for relation %s", SPI_getrelname(relation));

  entry->relid = RelationGetRelid(relation);
  entry->plan = plan;
}

SPIPlanPtr InfluxGetPlanFor(Relation relation) {
  Oid relid = RelationGetRelid(relation);
  InfluxPlanCacheEntry* entry;
  bool found;

  if (!influxdb_plan_cache) {
    HASHCTL ctl;
    ctl.keysize = sizeof(Oid);
    ctl.entrysize = sizeof(InfluxPlanCacheEntry);
    influxdb_plan_cache = hash_create(
        "InfluxDB Relation Plan Cache", 32, &ctl, HASH_ELEM | HASH_BLOBS);
    CacheRegisterRelcacheCallback(InfluxInvalidatePlan, 0);
  }

  entry = hash_search(influxdb_plan_cache, &relid, HASH_ENTER, &found);

  if (!found)
    InfluxCreatePlan(entry, relation);

  return entry->plan;
}
