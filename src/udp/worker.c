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

#include "worker.h"

#include <postgres.h>

#include <access/xact.h>
#include <catalog/namespace.h>
#include <executor/spi.h>
#include <pgstat.h>
#include <postmaster/bgworker.h>
#include <postmaster/interrupt.h>
#include <storage/ipc.h>
#include <utils/backend_status.h>
#include <utils/guc.h>
#include <utils/memutils.h>
#include <utils/resowner.h>
#include <utils/snapmgr.h>

#include <errno.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

#include <sys/socket.h>

#include "config.h"
#include "exec/insert.h"
#include "influxdb.h"
#include "network.h"

/* Maximum UDP datagram size (64 KB) */
#define UDP_BUFFER_SIZE (64 * 1024)

void InfluxUdpWorkerInitState(InfluxUdpWorkerState *state) {
  struct sockaddr_in addr;
  socklen_t addrlen = sizeof(addr);

  memset(state, 0, sizeof(*state));

  state->read_fd = InfluxNetworkUdpCreate(
      influxdb_udp_service, (struct sockaddr *)&addr, &addrlen);

  StartTransactionCommand();
  state->nspoid = get_namespace_oid(influxdb_udp_schema, false);
  CommitTransactionCommand();
}

void InfluxUdpWorkerMain(Datum arg) {
  InfluxUdpWorkerState state;
  ResourceOwner resowner;
  char buffer[UDP_BUFFER_SIZE];

  /* Establish signal handlers; once that's done, unblock signals. */
  pqsignal(SIGTERM, SignalHandlerForShutdownRequest);
  pqsignal(SIGHUP, SignalHandlerForConfigReload);
  BackgroundWorkerUnblockSignals();

  Assert(CurrentResourceOwner == NULL);
  resowner = ResourceOwnerCreate(NULL, "InfluxUdpWorkerMain");
  CurrentResourceOwner = resowner;
  CurrentMemoryContext = AllocSetContextCreate(
      TopMemoryContext, "InfluxUdpWorker", ALLOCSET_DEFAULT_SIZES);

  elog(LOG, "InfluxDB UDP Worker connecting to database %s", influxdb_database);
  BackgroundWorkerInitializeConnection(influxdb_database, NULL, 0);

  CurrentResourceOwner = resowner;

  pgstat_report_activity(STATE_RUNNING, "initializing worker state");

  InfluxUdpWorkerInitState(&state);

  while (!ShutdownRequestPending) {
    ssize_t len;
    MemoryContext oldcontext = CurrentMemoryContext;
    ResourceOwner oldowner = CurrentResourceOwner;

    CHECK_FOR_INTERRUPTS();

    if (ConfigReloadPending) {
      pgstat_report_activity(STATE_RUNNING, "reading configuration");
      ConfigReloadPending = false;
      ProcessConfigFile(PGC_SIGHUP);
    }

    pgstat_report_activity(STATE_IDLE, "waiting for input");

    len = recvfrom(state.read_fd, buffer, UDP_BUFFER_SIZE, 0, NULL, NULL);
    if (len <= 0) {
      if (errno == EINTR)
        continue;
      ereport(LOG, errcode_for_socket_access(), errmsg("recvfrom failed: %m"));
      continue;
    }

    pgstat_report_activity(STATE_RUNNING, "processing data");

    PG_TRY();
    {
      int err;

      SetCurrentStatementStartTimestamp();
      StartTransactionCommand();

      if ((err = SPI_connect()) != SPI_OK_CONNECT)
        elog(ERROR, "SPI_connect failed: %s", SPI_result_code_string(err));

      PushActiveSnapshot(GetTransactionSnapshot());

      process_text_internal(state.nspoid, buffer, len, 1);

      if ((err = SPI_finish()) != SPI_OK_FINISH)
        elog(ERROR, "SPI_finish failed: %s", SPI_result_code_string(err));

      PopActiveSnapshot();
      CommitTransactionCommand();
    }
    PG_CATCH();
    {
      MemoryContextSwitchTo(oldcontext);

      HOLD_INTERRUPTS();

      EmitErrorReport();
      AbortOutOfAnyTransaction();
      FlushErrorState();

      RESUME_INTERRUPTS();

      MemoryContextSwitchTo(oldcontext);
      CurrentResourceOwner = oldowner;
    }
    PG_END_TRY();

    CurrentResourceOwner = resowner;
  }

  close(state.read_fd);

  proc_exit(0);
}

void InfluxUdpWorkerInit(BackgroundWorker *worker) {
  memset(worker, 0, sizeof(*worker));

  worker->bgw_flags =
      BGWORKER_SHMEM_ACCESS | BGWORKER_BACKEND_DATABASE_CONNECTION;

  elog(DEBUG1, "%s: initializing UDP worker", __func__);

  worker->bgw_start_time = BgWorkerStart_RecoveryFinished;
  sprintf(worker->bgw_library_name, INFLUXDB_LIBRARY_NAME);
  sprintf(worker->bgw_function_name, INFLUXDB_UDP_FUNCTION_NAME);
  snprintf(worker->bgw_name, BGW_MAXLEN, "InfluxDB UDP protocol worker");
  snprintf(worker->bgw_type, BGW_MAXLEN, "InfluxDB UDP protocol worker");

  if (influxdb_http_worker_restart_time > 0)
    worker->bgw_restart_time = influxdb_http_worker_restart_time;
  else
    worker->bgw_restart_time = BGW_NEVER_RESTART;
}
