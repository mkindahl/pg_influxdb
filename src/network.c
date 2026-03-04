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

#include "network.h"

#include <postgres.h>
#include <fmgr.h>

#include <common/ip.h>
#include <miscadmin.h>
#include <utils/builtins.h>
#include <utils/elog.h>

#include <memory.h>

#include "influxdb.h"

#define LOG_ADDRSTR(ADDR, ADDRLEN)                                          \
  do {                                                                      \
    char host[NI_MAXHOST], service[NI_MAXSERV];                             \
    if ((ADDRLEN) > 0) {                                                    \
      if (getnameinfo((ADDR),                                               \
                      (ADDRLEN),                                            \
                      host,                                                 \
                      sizeof(host),                                         \
                      service,                                              \
                      sizeof(service),                                      \
                      NI_NUMERICSERV) == 0)                                 \
        elog(DEBUG1, "%s: testing address %s:%s", __func__, host, service); \
    }                                                                       \
  } while (0)

static void ConfigUdp(int fd) {
  int yes = 1;
  int read_buffer_bytes = 1024 * influxdb_udp_read_buffer;

  setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, sizeof(int));

  if (read_buffer_bytes > 0)
    setsockopt(fd,
               SOL_SOCKET,
               SO_RCVBUF,
               &read_buffer_bytes,
               sizeof(read_buffer_bytes));
}

static void ConfigHttp(int fd) {
  int yes = 1;
  setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, sizeof(int));
}

static int InfluxResolveAddress(const char* service, int socktype,
                                void (*config)(int), struct sockaddr* addr_out,
                                socklen_t* addrlen) {
  int fd, err;
  struct addrinfo hints, *addrs, *addr;

  memset(&hints, 0, sizeof(struct addrinfo));
  hints.ai_family = AF_INET;
  hints.ai_flags = AI_PASSIVE;
  hints.ai_socktype = socktype;
  hints.ai_protocol = 0;
  hints.ai_canonname = NULL;
  hints.ai_addr = NULL;
  hints.ai_next = NULL;

  err = pg_getaddrinfo_all(NULL, service, &hints, &addrs);
  if (err)
    ereport(ERROR,
            (errmsg("could not resolve service: %s\n", gai_strerror(err))));

  for (addr = addrs; addr; addr = addr->ai_next) {
    fd = socket(addr->ai_family, socktype, addr->ai_protocol);
    if (fd == PGINVALID_SOCKET)
      continue;

    (*config)(fd);

    LOG_ADDRSTR(addr->ai_addr, addr->ai_addrlen);

    if (bind(fd, addr->ai_addr, addr->ai_addrlen) == 0)
      break;

    close(fd);
  }

  if (!addr)
    ereport(ERROR,
            (errcode_for_socket_access(),
             errmsg("could not find any address: %m")));

  Assert(fd >= 0);

  if (addr_out) {
    Assert(addr->ai_addrlen <= addrlen);
    *addrlen = addr->ai_addrlen;
    memcpy(addr_out, addr->ai_addr, addr->ai_addrlen);
  }

  pg_freeaddrinfo_all(hints.ai_family, addrs);

  return fd;
}

int InfluxNetworkListenerCreate(const char* service, struct sockaddr* addr,
                                socklen_t* addrlen) {
  int fd =
      InfluxResolveAddress(service, SOCK_STREAM, ConfigHttp, addr, addrlen);

  if (listen(fd, 10) == -1)
    ereport(ERROR,
            (errcode_for_socket_access(),
             errmsg("could not listen on socket: %m")));

  if (InfluxNetworkSetNonblocking(fd) == -1)
    ereport(ERROR,
            (errcode_for_socket_access(),
             errmsg("could not set socket non-blocking: %m")));

  return fd;
}

int InfluxNetworkUdpCreate(const char* service, struct sockaddr* addr,
                           socklen_t* addrlen) {
  return InfluxResolveAddress(service, SOCK_DGRAM, ConfigUdp, addr, addrlen);
}
