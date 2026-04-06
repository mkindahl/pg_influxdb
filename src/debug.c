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

#include <postgres.h>

#include <commands/trigger.h>
#include <funcapi.h>

PG_FUNCTION_INFO_V1(trigger_fatal_error);

Datum trigger_fatal_error(PG_FUNCTION_ARGS) {
  TriggerData *trigdata = (TriggerData *)fcinfo->context;

  elog(FATAL,
       "FATAL error generated for table %s",
       RelationGetRelationName(trigdata->tg_relation));

  PG_RETURN_NULL();
}
