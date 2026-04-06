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

#ifndef HTTP_PARAMS_H_
#define HTTP_PARAMS_H_

#include <postgres.h>

#include "http/worker.h"

typedef struct InfluxHttpParamHandler {
  const char* param;
  size_t length;
  void (*cmd)(InfluxHttpRequestData* data, const char* val, size_t len);
} InfluxHttpParamHandler;

extern void InfluxParseParams(InfluxHttpRequestData* data, const char* start,
                              InfluxHttpParamHandler* handler);

extern InfluxHttpParamHandler InfluxWriteParamHandler[];

#endif /* HTTP_PARAMS_H_ */