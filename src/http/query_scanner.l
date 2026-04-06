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

%top{
#include <postgres.h>
#include <utils/palloc.h>

#include "common/utils.h"

typedef void *yyscan_t;
#include "query_parser.h"
#define YYSTYPE QUERY_YYSTYPE
}

%option reentrant bison-bridge case-insensitive 8bit
%option noinput noyywrap nounput
%option noyyalloc noyyrealloc noyyfree
%option prefix="query_yy"

IDENT [[:alpha:]][[:alnum:]_]*
UTF8-2     [\xc0-\xdf][\x80-\xbf]
UTF8-3     [\xe0-\xef][\x80-\xbf][\x80-\xbf]
UTF8-4     [\xf0-\xf7][\x80-\xbf][\x80-\xbf][\x80-\xbf]
UTF8       {UTF8-2}|{UTF8-3}|{UTF8-4}
QQSTRING   \"(\\.|{UTF8}|[^\\\n\"])+\"
QQUNTERM   \"(\\.|{UTF8}|[^\\\n\"])+

%%

[[:space:]]+    /* skip whitespace */
"CREATE"        return CREATE;
"DATABASE"      return DATABASE;
{QQSTRING}      { yylval->string = pnstrdup(yytext + 1, yyleng - 2); return IDENTIFIER; }
{IDENT}         { yylval->string = pnstrdup(yytext, yyleng); return IDENTIFIER; }
{QQUNTERM}        SYNTAX_ERROR("EOF in string literal", "trying to scan '%s'", yytext);
.               return *yytext;

%%

void *query_yyalloc(yy_size_t bytes, yyscan_t yyscanner) {
  (void) yyscanner;
  return palloc(bytes);
}

void *query_yyrealloc(void *ptr, yy_size_t bytes, yyscan_t yyscanner) {
  (void) yyscanner;
  if (ptr)
    return repalloc(ptr, bytes);
  else
    return palloc(bytes);
}

void query_yyfree(void *ptr, yyscan_t yyscanner) {
  (void) yyscanner;
  if (ptr)
    pfree(ptr);
}
