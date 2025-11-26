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
