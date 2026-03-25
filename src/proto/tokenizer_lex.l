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

%{

/*
 * Do *not* include the generated tokenizer_lex.h here: (f)lex is not
 * designed for that.
 */

#include <postgres.h>

#include "common/utils.h"
#include "parser.h"
#include "influxdb.h"

#define MAYBE_REMOVE_QUOTES()    \
  do {                           \
    if (!influxdb_keep_quotes) { \
      ++yytext;                  \
      yyleng -= 2;               \
    }                            \
  } while (0)

%}

SIGN       [+-]
DIGITS     [[:digit:]]+
NUMBER     {SIGN}?{DIGITS}
SYMBOL     [^,= \\\n]([^,= \\\n]|\\.)*
FLOAT      {NUMBER}\.{DIGITS}([eE]{SIGN}{DIGITS})?
UTF8-2     [\xc0-\xdf][\x80-\xbf]
UTF8-3     [\xe0-\xef][\x80-\xbf][\x80-\xbf]
UTF8-4     [\xf0-\xf7][\x80-\xbf][\x80-\xbf][\x80-\xbf]
UTF8       {UTF8-2}|{UTF8-3}|{UTF8-4}
QQSTRING   \"(\\.|{UTF8}|[^\\\n\"])+\"
QSTRING    '(\\.|{UTF8}|[^\\\n'])+\'
QQUNTERM   \"(\\.|{UTF8}|[^\\\n\"])+
QUNTERM    '(\\.|{UTF8}|[^\\\n'])+

%option reentrant never-interactive 8bit
%option header-file="tokenizer_lex.h"
%option nounput noinput noyywrap
%option noyyalloc noyyrealloc noyyfree
%option debug

%%
"#".*             ;
{NUMBER}i         yyleng--; return TOKEN_KIND_INTEGER;
{NUMBER}u         yyleng--; return TOKEN_KIND_UINTEGER;
{NUMBER}          return TOKEN_KIND_NUMBER;
{FLOAT}           return TOKEN_KIND_FLOAT;
(?i:T|TRUE)       |
(?i:F|FALSE)      return TOKEN_KIND_BOOLEAN;
{QQSTRING}        |
{QSTRING}         MAYBE_REMOVE_QUOTES(); return TOKEN_KIND_STRING;
[[:blank:]]+      return TOKEN_KIND_BLANK;
{SYMBOL}          return TOKEN_KIND_SYMBOL;
{QUNTERM}         |
{QQUNTERM}        SYNTAX_ERROR("EOF in string literal", "trying to scan '%s'", yytext);
\r?\n             return TOKEN_KIND_END_OF_LINE;
(?s:.)            return *yytext;
%%

static InfluxToken MakeToken(InfluxTokenKind kind, char *ptr, size_t len) {
  return (InfluxToken){.kind = kind, .buf = ptr, .len = len};
}

/*
 * Initialize the scan state.
 *
 * We use yy_scan_bytes (which copies the string) rather than
 * yy_scan_buffer (which does not copy the string) since the latter
 * requires two terminating NUL and we might use a VARLEN type as
 * input, hence we would need to take a copy of it to be able to add
 * the two terminating NUL bytes, so we can just as well take a copy
 * of it here.
 *
 * TODO: we could switch the buffer to use a StringInfo instead and
 * initializer it using initReadOnlyStringInfo().
 */
void InfluxParseStateInit(InfluxParseState *state, char *buf, size_t len) {
  memset(state, 0, sizeof(*state));
  yylex_init(&state->scanner);
  state->buf = yy_scan_bytes(buf, len, state->scanner);
}

void InfluxParseStateFinish(InfluxParseState *state) {
  yy_delete_buffer(state->buf, state->scanner);
  yylex_destroy(state->scanner);
}

bool InfluxParseStateHasMore(InfluxParseState *state) {
    struct yyguts_t *yyg = (struct yyguts_t*)state->scanner;
    int pos, remaining;
    
    if (!YY_CURRENT_BUFFER)
        return false;
    
    pos = yyg->yy_c_buf_p - YY_CURRENT_BUFFER_LVALUE->yy_ch_buf;
    remaining = yyg->yy_n_chars - pos;
    
    if (YY_CURRENT_BUFFER_LVALUE->yy_buffer_status == YY_BUFFER_EOF_PENDING)
        return false;
    
    return (remaining > 0);
}

InfluxToken InfluxNextToken(InfluxParseState *state) {
  int kind = yylex(state->scanner);
  char *text = yyget_text(state->scanner);
  size_t leng = yyget_leng(state->scanner);
  return MakeToken(kind, text, leng);
}

void *yyalloc(yy_size_t bytes, yyscan_t yyscanner) { return palloc(bytes); }

void *yyrealloc(void *ptr, yy_size_t bytes, yyscan_t yyscanner) {
  if (ptr)
    return repalloc(ptr, bytes);
  else
    return palloc(bytes);
}

void yyfree(void *ptr, yyscan_t yyscanner) {
  if (ptr) pfree(ptr);
}
