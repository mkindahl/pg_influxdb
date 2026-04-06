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

#ifndef UDP_WORKER_H_
#define UDP_WORKER_H_

#include <postgres.h>

#include <c.h>
#include <postmaster/bgworker.h>

typedef struct InfluxUdpWorkerState {
  int read_fd;
  Oid nspoid;
} InfluxUdpWorkerState;

extern PGDLLEXPORT void InfluxUdpWorkerMain(Datum arg);

extern void InfluxUdpWorkerInitState(InfluxUdpWorkerState* state);
extern void InfluxUdpWorkerInit(BackgroundWorker* worker);

#endif /* UDP_WORKER_H_ */
