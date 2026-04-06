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

#ifndef NETWORK_H_
#define NETWORK_H_

#include <fcntl.h>

#include <sys/socket.h>
#include <sys/types.h>

static inline int InfluxNetworkSetNonblocking(int fd) {
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags == -1)
    return -1;
  return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

int InfluxNetworkListenerCreate(const char* service, struct sockaddr* addr,
                                socklen_t* addrlen);
int InfluxNetworkUdpCreate(const char* service, struct sockaddr* addr,
                           socklen_t* addrlen);

#endif /* NETWORK_H_ */
