#include "utils.h"

#include <postgres.h>

#include "parser.h"

Jsonb *InfluxBuildJsonObject(List *items) {
  JsonbParseState *state = NULL;
  return JsonbValueToJsonb(InfluxJsonbAddPairs(&state, items));
}
