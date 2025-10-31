#include <postgres.h>

#include <nodes/pg_list.h>
#include <utils/jsonb.h>

#include <stdlib.h>

/*
 * Do *not* include "tokenizer.h" since this file is indirectly
 * included by the generated implementation file, which causes
 * problems due to multiple header file inclusions. Instead we define
 * the types ourself here.
 */

typedef void* yyscan_t;
typedef struct yy_buffer_state* YY_BUFFER_STATE;

/**
 * Token kind.
 *
 * The lowest 127 are reserved for single-char tokens and zero is used
 * for end-of-input.
 */
typedef enum InfluxTokenKind {
  TOKEN_KIND_END = 0,     /* Used for end of input */
  TOKEN_KIND_FLOAT = 128, /* What looks like a real float */
  TOKEN_KIND_NUMBER,      /* Sequence of digits, which is either a float or a
                             timestamp */
  TOKEN_KIND_INTEGER,     /* Sequence of digits with a trailing "i" */
  TOKEN_KIND_UINTEGER,    /* Sequence of digits with a trailing "u" */
  TOKEN_KIND_BLANK,       /* One or more whitespace characters */
  TOKEN_KIND_STRING,      /* String with quotes */
  TOKEN_KIND_SYMBOL,      /* String without quotes */
  TOKEN_KIND_BOOLEAN,     /* String without quotes that looks like a boolean */
} InfluxTokenKind;

typedef struct InfluxToken {
  uint32 kind;
  const char* buf;
  size_t len;
} InfluxToken;

typedef struct InfluxPair {
  InfluxToken key;
  InfluxToken val;
} InfluxPair;

typedef struct InfluxDataPoint {
  InfluxToken measurement;
  List* tags;
  List* fields;
  InfluxToken timestamp;
} InfluxDataPoint;

typedef struct InfluxParseState {
  yyscan_t scanner;
  YY_BUFFER_STATE buf;
  InfluxDataPoint* data_point;
} InfluxParseState;

extern void InfluxParseBuffer(InfluxDataPoint* data_point, char* buf,
                              size_t len);
extern InfluxToken InfluxNextToken(InfluxParseState* state);
extern void InfluxParseStateInit(InfluxParseState* state,
                                 InfluxDataPoint* data_point, char* buf,
                                 size_t len);
extern void InfluxParseStateFinish(InfluxParseState* state);
extern const char* KindName(int kind);

extern StringInfo InfluxTokenGetString(InfluxToken* token);
extern JsonbValue InfluxTokenGetJsonbValue(InfluxToken* token);
extern JsonbValue* InfluxJsonbAddPairs(JsonbParseState** state, List* items);
extern Jsonb* DataPointGetJsonB(InfluxDataPoint* data_point);
extern void InfluxParseDataPoint(InfluxParseState* state);
