#include "http/params.h"

#include <postgres.h>

#include <catalog/namespace.h>

#include <stdlib.h>

#include "common/utils.h"
#include "http/worker.h"

static struct {
  const char* precision;
  size_t length;
  int64 multiplier;
} multipliers[] = {
    {STR_LIT("ns"), 1},
    {STR_LIT("us"), 1000L},
    {STR_LIT("ms"), 1000000L},
    {STR_LIT("s"), 1000000000L},
    {STR_LIT("m"), 60L * 1000000000L},
    {STR_LIT("h"), 60L * 60L * 1000000000L},
};

/*
 * Function: get_precision_multiplier
 * Description: Returns the multiplier for the given precision string.
 */
static int64 get_precision_multiplier(const char* val, size_t len) {
  for (int i = 0; i < lengthof(multipliers); ++i) {
    if (multipliers[i].length == len &&
        strncmp(val, multipliers[i].precision, len) == 0)
      return multipliers[i].multiplier;
  }

  return -1;
}

/*
 * Function: handle_write_param_db
 * Description: Handles the 'db' parameter for the write operation. It sets the
 * database OID for the request.
 */
static void handle_write_param_db(InfluxHttpRequestData* data, const char* val,
                                  size_t len) {
  char name[NAMEDATALEN] = {0};
  Assert(len < NAMEDATALEN);
  memcpy(name, val, len);
  data->nspoid = get_namespace_oid(name, false);
}

/*
 * Function: handle_write_param_precision
 * Description: Handles the 'precision' parameter for the write operation. It
 * sets the precision multiplier for time values. Unrecognized precision values
 * will result in an error.
 */
static void handle_write_param_precision(InfluxHttpRequestData* data,
                                         const char* val, size_t len) {
  data->precision_multiplier = get_precision_multiplier(val, len);
}

/*
 * Function: handle_write_param_user
 * Description: Handles the 'u' parameter for the write operation. It stores the
 * username for authentication.
 */
static void handle_write_param_user(InfluxHttpRequestData* data,
                                    const char* val, size_t len) {
  MemoryContext oldcontext = MemoryContextSwitchTo(data->mcxt);
  data->query_user = pnstrdup(val, len);
  MemoryContextSwitchTo(oldcontext);
}

/*
 * Function: handle_write_param_pass
 * Description: Handles the 'p' parameter for the write operation. It stores the
 * password for authentication.
 */
static void handle_write_param_pass(InfluxHttpRequestData* data,
                                    const char* val, size_t len) {
  MemoryContext oldcontext = MemoryContextSwitchTo(data->mcxt);
  data->query_pass = pnstrdup(val, len);
  MemoryContextSwitchTo(oldcontext);
}

/*
 * Function: handle_param
 * Description: Handles parameter parsing for the write operation. Unrecognized
 * parameters are ignored.
 */
static void handle_param(InfluxHttpRequestData* data, const char* key,
                         const char* val, const char* endptr,
                         InfluxHttpParamHandler* handler) {
  const size_t keylen = (val - 1) - key;
  const size_t vallen = endptr - val;
  for (int i = 0; handler[i].param != NULL; ++i)
    if (handler[i].length == keylen &&
        strncmp(key, handler[i].param, keylen) == 0)
      return (*handler[i].cmd)(data, val, vallen);
}

/*
 * Function: InfluxParseParams
 * Description: Parses HTTP parameters.
 */
void InfluxParseParams(InfluxHttpRequestData* data, const char* start,
                       InfluxHttpParamHandler* params) {
  const char* key = start + 1;
  const char* val = NULL;
  const char* ptr;

  /* If it doesn't start with a '?', there are no parameters */
  if (*start != '?')
    return;

  /* From RFC 3986 3.4:
   *
   *   The query component is indicated by the first question mark
   *   ("?")  character and terminated by a number sign ("#")
   *   character or by the end of the URI.
   *
   * Here the query component will start after the question mark and
   * end with the first space (which is followed by the HTTP version).
   */
  for (ptr = start + 1; *ptr != '#' && *ptr != ' '; ++ptr) {
    if (*ptr == '=') {
      val = ptr + 1;
    } else if (*ptr == '&') {
      Assert(val != NULL && key != NULL);
      handle_param(data, key, val, ptr, params);
      key = ptr + 1; /* Start of next key */
      val = NULL;    /* The value does not exist here */
    }
  }

  /* Handle last parameter, if there were one */
  if (val)
    handle_param(data, key, val, ptr, params);
}

InfluxHttpParamHandler InfluxWriteParamHandler[] = {
    {STR_LIT("db"), handle_write_param_db},
    {STR_LIT("precision"), handle_write_param_precision},
    {STR_LIT("u"), handle_write_param_user},
    {STR_LIT("p"), handle_write_param_pass},
    {NULL, 0, NULL} /* Sentinel */
};
