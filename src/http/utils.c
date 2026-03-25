#include "http/utils.h"

#include <postgres.h>
#include <fmgr.h>

#include <utils/builtins.h>

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
