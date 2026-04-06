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

#ifndef UTILS_H_
#define UTILS_H_

#include <postgres.h>

#include <nodes/pg_list.h>
#include <utils/jsonb.h>

#define STR_LIT(str) str, sizeof(str) - 1

#define SYNTAX_ERROR(MSG, DETAIL, ...)   \
  ereport(ERROR,                         \
          errcode(ERRCODE_SYNTAX_ERROR), \
          errmsg(MSG),                   \
          errdetail(DETAIL, __VA_ARGS__))

extern void InfluxJsonbAddKeyValue(JsonbParseState** state, const char* key,
                                   const char* value);
extern Jsonb* InfluxErrorDataGetJsonb(ErrorData* edata);

#endif /* UTILS_H_ */
