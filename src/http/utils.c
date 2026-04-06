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

#include "http/utils.h"

#include <postgres.h>
#include <fmgr.h>

#include <utils/builtins.h>

#include "http/http_parser.h"

PG_FUNCTION_INFO_V1(url_decode_text);

Datum url_decode_text(PG_FUNCTION_ARGS) {
  text* input = PG_GETARG_TEXT_PP(0);
  char* str = text_to_cstring(input);
  url_decode(str);
  PG_RETURN_TEXT_P(cstring_to_text(str));
}

static int hex_digit(char c) {
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'A' && c <= 'F')
    return c - 'A' + 10;
  if (c >= 'a' && c <= 'f')
    return c - 'a' + 10;
  return -1;
}

void url_decode(char* s) {
  char* src = s;
  char* dst = s;
  while (*src) {
    if (*src == '+') {
      *dst++ = ' ';
      src++;
    } else if (*src == '%' && src[1] && src[2]) {
      int hi = hex_digit(src[1]);
      int lo = hex_digit(src[2]);
      if (hi >= 0 && lo >= 0) {
        *dst++ = (char)((hi << 4) | lo);
        src += 3;
      } else {
        *dst++ = *src++;
      }
    } else {
      *dst++ = *src++;
    }
  }
  *dst = '\0';
}

/*
 * Function: allow_header_string
 * Description: Generates the Allow header string for the given allowed methods.
 */
const char* allow_header_string(unsigned int allowed_methods) {
  StringInfoData buf;
  initStringInfo(&buf);
  for (int i = 0; i < 8 * sizeof(allowed_methods); ++i) {
    if (allowed_methods & (1 << i)) {
      if (buf.len > 0)
        appendStringInfoString(&buf, ", ");
      appendStringInfoString(&buf, http_method_str(i));
    }
  }
  return buf.data;
}
