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

#include "table.h"

#include <postgres.h>

#include <catalog/pg_class.h>
#include <catalog/pg_type.h>
#include <commands/tablecmds.h>
#include <miscadmin.h>
#include <nodes/makefuncs.h>
#include <nodes/parsenodes.h>
#include <utils/lsyscache.h>

Oid InfluxCreateTable(Oid nspid, InfluxDataPoint* data_point,
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
