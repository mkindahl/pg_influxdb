#ifndef PLANS_H_
#define PLANS_H_

#include <postgres.h>

#include <executor/spi.h>

#pragma once

typedef struct InfluxPlanCacheEntry {
  Oid relid;
  SPIPlanPtr plan;
} InfluxPlanCacheEntry;

extern SPIPlanPtr InfluxGetPlanFor(Relation relation);

#endif /* PLANS_H_ */
