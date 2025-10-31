#ifndef UTILS_H_
#define UTILS_H_

#include <postgres.h>

#include <nodes/pg_list.h>
#include <utils/jsonb.h>

extern Jsonb *InfluxBuildJsonObject(List *items);

#endif /* UTILS_H_ */
