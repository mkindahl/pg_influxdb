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

#include "utils.h"

#include <postgres.h>

void InfluxJsonbAddKeyValue(JsonbParseState** state, const char* key,
                            const char* val) {
  JsonbValue jb_key, jb_val;

  elog(DEBUG1, "adding %s message %s", key, val);

  jb_key.type = jbvString;
  jb_key.val.string.val = (char*)key;
  jb_key.val.string.len = strlen(key);

  pushJsonbValue(state, WJB_KEY, &jb_key);

  jb_val.type = jbvString;
  jb_val.val.string.val = (char*)val;
  jb_val.val.string.len = strlen(val);

  (void)pushJsonbValue(state, WJB_VALUE, &jb_val);
}

Jsonb* InfluxErrorDataGetJsonb(ErrorData* edata) {
  JsonbParseState* state = NULL;
  JsonbValue* result;

  (void)pushJsonbValue(&state, WJB_BEGIN_OBJECT, NULL);

  InfluxJsonbAddKeyValue(&state, "error", edata->message);
  if (edata->detail)
    InfluxJsonbAddKeyValue(&state, "detail", edata->detail);

  result = pushJsonbValue(&state, WJB_END_OBJECT, NULL);

  return JsonbValueToJsonb(result);
}
