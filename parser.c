/**
 * Recursive decent parser for InfluxDB Line Protocol (ILP).
 *
 * <measurement>[,<tag_key>=<tag_value>[,<tag_key>=<tag_value>]]
 * <field_key>=<field_value>[,<field_key>=<field_value>] [<timestamp>]
 */

#include "parser.h"

#include <postgres.h>
#include <fmgr.h>

#include <funcapi.h>
#include <lib/stringinfo.h>
#include <port.h>
#include <utils/builtins.h>
#include <utils/elog.h>
#include <utils/jsonb.h>
#include <utils/palloc.h>

#include <stdlib.h>
#include <string.h>

static InfluxToken ParseTags(InfluxParseState* state,
                             InfluxDataPoint* data_point);
static InfluxToken ParseFields(InfluxParseState* state,
                               InfluxDataPoint* data_point);

PG_FUNCTION_INFO_V1(tokenize);
PG_FUNCTION_INFO_V1(parse_text);

#define SYNTAX_ERROR(EXPECT, TOKEN)                \
  do {                                             \
    ereport(ERROR,                                 \
            errcode(ERRCODE_SYNTAX_ERROR),         \
            errmsg("syntax error"),                \
            errdetail("Expected %s, saw %s '%s'.", \
                      (EXPECT),                    \
                      KindName((TOKEN)->kind),     \
                      (TOKEN)->buf));              \
  } while (0)

static inline bool TokenIsValid(InfluxToken token) {
  return token.kind != TOKEN_KIND_END_OF_INPUT;
}

static inline bool TokenIsKey(InfluxToken token) {
  switch (token.kind) {
    case TOKEN_KIND_SYMBOL:
    case TOKEN_KIND_STRING:
      return true;
    default:
      return false;
  }
}

static inline bool TokenIsValue(InfluxToken token) {
  switch (token.kind) {
    case TOKEN_KIND_FLOAT:
    case TOKEN_KIND_NUMBER:
    case TOKEN_KIND_INTEGER:
    case TOKEN_KIND_UINTEGER:
    case TOKEN_KIND_STRING:
    case TOKEN_KIND_SYMBOL:
    case TOKEN_KIND_BOOLEAN:
      return true;

    default:
      return false;
  }
}

const char* KindName(int kind) {
  static const char* kind_name[] = {
      [TOKEN_KIND_END_OF_INPUT] = "END",
      [TOKEN_KIND_END_OF_LINE] = "EOL",
      [TOKEN_KIND_FLOAT] = "FLOAT",
      [TOKEN_KIND_NUMBER] = "NUMBER",
      [TOKEN_KIND_INTEGER] = "INTEGER",
      [TOKEN_KIND_UINTEGER] = "UINTEGER",
      [TOKEN_KIND_BLANK] = "BLANK",
      [TOKEN_KIND_STRING] = "STRING",
      [TOKEN_KIND_SYMBOL] = "SYMBOL",
      [TOKEN_KIND_BOOLEAN] = "BOOLEAN",
  };

  if (kind_name[kind]) {
    return kind_name[kind];
  } else {
    static char buf[16];
    buf[0] = kind;
    buf[1] = 0;
    return buf;
  }
}

/**
 * Parse a key-value pair in either tags or fields.
 */
static void ParseKeyValue(InfluxParseState* state, InfluxToken* key,
                          InfluxToken* value) {
  InfluxToken sep;

  *key = InfluxNextToken(state);
  if (!TokenIsKey(*key))
    SYNTAX_ERROR("symbol", key);

  sep = InfluxNextToken(state);
  if (sep.kind != '=')
    SYNTAX_ERROR("'='", &sep);

  *value = InfluxNextToken(state);
  if (!TokenIsValue(*value))
    SYNTAX_ERROR("value", value);
}

static InfluxToken ParseTags(InfluxParseState* state,
                             InfluxDataPoint* data_point) {
  InfluxToken next;
  while (true) {
    InfluxPair* tag = palloc(sizeof(*tag));

    ParseKeyValue(state, &tag->key, &tag->val);

    data_point->tags = lappend(data_point->tags, tag);

    next = InfluxNextToken(state);

    if (next.kind == TOKEN_KIND_BLANK)
      break;

    if (next.kind != ',')
      SYNTAX_ERROR("',' or blank", &next);
  }
  return next;
}

static InfluxToken ParseFields(InfluxParseState* state,
                               InfluxDataPoint* data_point) {
  InfluxToken next;

  while (true) {
    InfluxPair* field = palloc(sizeof(*field));

    ParseKeyValue(state, &field->key, &field->val);

    data_point->fields = lappend(data_point->fields, field);

    next = InfluxNextToken(state);

    if (next.kind == TOKEN_KIND_BLANK || next.kind == TOKEN_KIND_END_OF_INPUT)
      break;

    if (next.kind != ',')
      ereport(ERROR,
              errcode(ERRCODE_SYNTAX_ERROR),
              errmsg("syntax error"),
              errdetail("Expected \",\" or blank, saw %s '%s'",
                        KindName(next.kind),
                        next.buf));
  }

  return next;
}

void InfluxParseDataPoint(InfluxParseState* state,
                          InfluxDataPoint* data_point) {
  InfluxToken measurement, token;

  memset(data_point, 0, sizeof(*data_point));

  measurement = InfluxNextToken(state);
  if (measurement.kind != TOKEN_KIND_SYMBOL &&
      measurement.kind != TOKEN_KIND_STRING)
    SYNTAX_ERROR("measurement name", &measurement);

  data_point->measurement = measurement;

  token = InfluxNextToken(state);
  if (token.kind == ',')
    token = ParseTags(state, data_point);

  if (token.kind != TOKEN_KIND_BLANK)
    SYNTAX_ERROR("blank", &token);

  token = ParseFields(state, data_point);
  if (token.kind == TOKEN_KIND_BLANK) {
    token = InfluxNextToken(state);
    if (token.kind != TOKEN_KIND_NUMBER)
      SYNTAX_ERROR("timestamp", &token);
    data_point->timestamp = token;
  }
  token = InfluxNextToken(state);
  if (token.kind != TOKEN_KIND_END_OF_INPUT &&
      token.kind != TOKEN_KIND_END_OF_LINE)
    SYNTAX_ERROR("end of line or end of input", &token);
}

static StringInfo RemoveBackslashes(const char* str, size_t len) {
  StringInfo info = makeStringInfo();
  const char* ptr = str;

  for (ptr = str; ptr < str + len; ++ptr) {
    if (*ptr != '\\')
      appendStringInfoCharMacro(info, *ptr);
  }

  return info;
}

StringInfo InfluxTokenGetString(InfluxToken* token) {
  switch (token->kind) {
    case TOKEN_KIND_STRING:
    case TOKEN_KIND_SYMBOL:
    case TOKEN_KIND_BOOLEAN:
    case TOKEN_KIND_FLOAT:
    case TOKEN_KIND_INTEGER:
    case TOKEN_KIND_UINTEGER:
    case TOKEN_KIND_NUMBER:
      return RemoveBackslashes(token->buf, token->len);
    default:
      elog(ERROR,
           "cannot convert token kind %d containing %s to string",
           token->kind,
           token->buf);
  }
}

JsonbValue* InfluxJsonbAddPairs(JsonbParseState** state, List* items) {
  JsonbValue jb_key, jb_val;
  ListCell* cell;

  (void)pushJsonbValue(state, WJB_BEGIN_OBJECT, NULL);

  foreach (cell, items) {
    InfluxPair* pair = (InfluxPair*)lfirst(cell);
    StringInfo key = InfluxTokenGetString(&pair->key);

    jb_key.type = jbvString;
    jb_key.val.string.val = key->data;
    jb_key.val.string.len = key->len;

    pushJsonbValue(state, WJB_KEY, &jb_key);

    jb_val = InfluxTokenGetJsonbValue(&pair->val);

    pushJsonbValue(state, WJB_VALUE, &jb_val);
  }

  return pushJsonbValue(state, WJB_END_OBJECT, NULL);
}

JsonbValue InfluxTokenGetJsonbValue(InfluxToken* token) {
  JsonbValue jb_val;
  Datum datum;
  StringInfo info;

  switch (token->kind) {
    case TOKEN_KIND_STRING:
    case TOKEN_KIND_SYMBOL:
      info = RemoveBackslashes(token->buf, token->len);
      jb_val.type = jbvString;
      jb_val.val.string.len = info->len;
      jb_val.val.string.val = info->data;
      break;

    case TOKEN_KIND_BOOLEAN:
      jb_val.type = jbvBool;
      jb_val.val.boolean = (toupper(*token->buf) == 'T');
      break;

    case TOKEN_KIND_FLOAT:
    case TOKEN_KIND_INTEGER:
    case TOKEN_KIND_UINTEGER:
    case TOKEN_KIND_NUMBER:
      jb_val.type = jbvNumeric;
      info = InfluxTokenGetString(token);
      datum = DirectFunctionCall3(numeric_in,
                                  CStringGetDatum(info->data),
                                  ObjectIdGetDatum(InvalidOid),
                                  Int32GetDatum(-1));
      jb_val.val.numeric = DatumGetNumeric(datum);
      break;
    default:
      elog(ERROR, "cannot convert token %s to JsonbValue", token->buf);
      break;
  }

  return jb_val;
}

Jsonb* DataPointGetJsonB(InfluxDataPoint* data_point) {
  JsonbValue jb_key, jb_val;
  JsonbValue* res;
  JsonbParseState* state = NULL;

  (void)pushJsonbValue(&state, WJB_BEGIN_OBJECT, NULL);

  /* Add measurement */
  jb_key.type = jbvString;
  jb_key.val.string.val = "measurement";
  jb_key.val.string.len = sizeof("measurement") - 1;

  pushJsonbValue(&state, WJB_KEY, &jb_key);

  jb_val = InfluxTokenGetJsonbValue(&data_point->measurement);
  pushJsonbValue(&state, WJB_VALUE, &jb_val);

  /* Add timestamp, if there is one */
  if (data_point->timestamp.kind == TOKEN_KIND_NUMBER) {
    jb_key.type = jbvString;
    jb_key.val.string.val = "time";
    jb_key.val.string.len = sizeof("time") - 1;

    pushJsonbValue(&state, WJB_KEY, &jb_key);

    jb_val = InfluxTokenGetJsonbValue(&data_point->timestamp);
    pushJsonbValue(&state, WJB_VALUE, &jb_val);
  }

  /* Add tags, if there are any */
  if (data_point->tags != NIL) {
    jb_key.type = jbvString;
    jb_key.val.string.val = "tags";
    jb_key.val.string.len = sizeof("tags") - 1;

    pushJsonbValue(&state, WJB_KEY, &jb_key);

    (void)InfluxJsonbAddPairs(&state, data_point->tags);
  }

  /* Add fields */
  jb_key.type = jbvString;
  jb_key.val.string.val = "fields";
  jb_key.val.string.len = sizeof("fields") - 1;

  pushJsonbValue(&state, WJB_KEY, &jb_key);

  (void)InfluxJsonbAddPairs(&state, data_point->fields);

  res = pushJsonbValue(&state, WJB_END_OBJECT, NULL);

  return JsonbValueToJsonb(res);
}

Datum parse_text(PG_FUNCTION_ARGS) {
  FuncCallContext* funcctx;
  InfluxParseState* state;
  text* input = PG_GETARG_TEXT_PP(0);

  if (SRF_IS_FIRSTCALL()) {
    MemoryContext oldcontext;

    funcctx = SRF_FIRSTCALL_INIT();
    oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

    state = palloc(sizeof(*state));

    InfluxParseStateInit(state, VARDATA_ANY(input), VARSIZE_ANY_EXHDR(input));

    funcctx->user_fctx = state;

    MemoryContextSwitchTo(oldcontext);
  }

  funcctx = SRF_PERCALL_SETUP();
  state = funcctx->user_fctx;

  if (InfluxParseStateHasMore(state)) {
    Jsonb* res;
    InfluxDataPoint data_point;

    InfluxParseDataPoint(state, &data_point);
    res = DataPointGetJsonB(&data_point);
    SRF_RETURN_NEXT(funcctx, PointerGetDatum(res));
  }

  InfluxParseStateFinish(state);

  SRF_RETURN_DONE(funcctx);
}

/*
 * Tokenize a string and return a set of tokens.
 *
 * Each token consists of a kind and the actual text of the token.
 *
 * This function is mostly intended for testing the tokenization function.
 */
Datum tokenize(PG_FUNCTION_ARGS) {
  InfluxParseState* state;
  FuncCallContext* funcctx;
  InfluxToken token;

  if (SRF_IS_FIRSTCALL()) {
    TupleDesc tupdesc;
    MemoryContext oldcontext;
    text* input = PG_GETARG_TEXT_PP(0);

    funcctx = SRF_FIRSTCALL_INIT();
    oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

    if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
      ereport(ERROR,
              (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
               errmsg("function returning record called in context "
                      "that cannot accept record")));

    funcctx->tuple_desc = BlessTupleDesc(tupdesc);

    state = palloc(sizeof(*state));
    funcctx->attinmeta = TupleDescGetAttInMetadata(tupdesc);
    funcctx->user_fctx = state;

    InfluxParseStateInit(state, VARDATA_ANY(input), VARSIZE_ANY_EXHDR(input));

    MemoryContextSwitchTo(oldcontext);
  }

  funcctx = SRF_PERCALL_SETUP();
  state = funcctx->user_fctx;

  token = InfluxNextToken(state);
  if (TokenIsValid(token)) {
    Datum values[2];
    bool nulls[2];
    HeapTuple tuple;
    Datum result;

    Assert(tupdesc->natts == 2);

    nulls[0] = false;
    values[0] = Int32GetDatum(token.kind);
    nulls[1] = false;
    values[1] = PointerGetDatum(cstring_to_text_with_len(token.buf, token.len));

    tuple = heap_form_tuple(funcctx->tuple_desc, values, nulls);
    result = HeapTupleGetDatum(tuple);

    SRF_RETURN_NEXT(funcctx, result);
  }

  InfluxParseStateFinish(state);
  SRF_RETURN_DONE(funcctx);
}
