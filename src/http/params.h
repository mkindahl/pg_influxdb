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