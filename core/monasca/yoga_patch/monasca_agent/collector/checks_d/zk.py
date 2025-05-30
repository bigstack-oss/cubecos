# (C) Copyright 2015 Hewlett Packard Enterprise Development Company LP
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

"""Parses the response from zookeeper's `stat` admin command, which looks like:

```
Zookeeper version: 3.2.2--1, built on 03/16/2010 07:31 GMT
Clients:
 /10.42.114.160:32634[1](queued=0,recved=12,sent=0)
 /10.37.137.74:21873[1](queued=0,recved=53613,sent=0)
 /10.37.137.74:21876[1](queued=0,recved=57436,sent=0)
 /10.115.77.32:32990[1](queued=0,recved=16,sent=0)
 /10.37.137.74:21891[1](queued=0,recved=55011,sent=0)
 /10.37.137.74:21797[1](queued=0,recved=19431,sent=0)

Latency min/avg/max: -10/0/20007
Received: 101032173
Sent: 0
Outstanding: 0
Zxid: 0x1034799c7
Mode: leader
Node count: 487
```

Tested with Zookeeper versions 3.0.0 to 3.4.10
"""

import re
import socket
import struct

from io import StringIO
from oslo_utils import encodeutils

from monasca_agent.collector.checks import AgentCheck


class Zookeeper(AgentCheck):
    version_pattern = re.compile(r'Zookeeper version: ([^.]+)\.([^.]+)\.([^-]+)', flags=re.I)

    def check(self, instance):
        host = instance.get('host', 'localhost')
        port = int(instance.get('port', 2181))
        timeout = float(instance.get('timeout', 3.0))
        dimensions = self._set_dimensions(
            {'component': 'zookeeper', 'service': 'zookeeper'}, instance)

        sock = socket.socket()
        sock.settimeout(timeout)
        buf = StringIO()
        chunk_size = 1024
        # try-finally and try-except to stay compatible with python 2.4
        try:
            try:
                # Connect to the zk client port and send the stat command
                sock.connect((host, port))
                sock.sendall(b'stat')

                # Read the response into a StringIO buffer
                chunk = encodeutils.safe_decode(sock.recv(chunk_size), 'utf-8')
                buf.write(chunk)
                num_reads = 1
                max_reads = 10000
                while chunk:
                    if num_reads > max_reads:
                        # Safeguard against an infinite loop
                        raise Exception(
                            "Read %s bytes before exceeding max reads of %s. " %
                            (buf.tell(), max_reads))
                    chunk = encodeutils.safe_decode(sock.recv(chunk_size), 'utf-8')
                    buf.write(chunk)
                    num_reads += 1
            except socket.timeout:
                buf = None
        finally:
            sock.close()

        if buf is not None:
            # Parse the response
            metrics, new_dimensions = self.parse_stat(buf)
            if new_dimensions is not None:
                dimensions.update(new_dimensions.copy())

            # Write the data
            for metric, value in metrics:
                self.gauge(metric, value, dimensions=dimensions)
        else:
            # Reading from the client port timed out, track it as a metric
            self.increment('zookeeper.timeouts', dimensions=dimensions)

    @classmethod
    def parse_stat(cls, buf):
        """`buf` is a readable file-like object

        returns a tuple: ([(metric_name, value)], dimensions)
        """
        metrics = []
        buf.seek(0)

        # Check the version line to make sure we parse the rest of the
        # body correctly. Particularly, the Connections val was added in
        # >= 3.4.4.
        start_line = buf.readline()
        match = cls.version_pattern.match(start_line)
        if match is None:
            raise Exception("Could not parse version from stat command output: %s" % start_line)
        else:
            version_tuple = match.groups()
        has_connections_val = list(map(int, version_tuple)) >= [3, 4, 4]

        # Clients:
        buf.readline()  # skip the Clients: header
        connections = 0
        client_line = buf.readline().strip()
        if client_line:
            connections += 1
        while client_line:
            client_line = buf.readline().strip()
            if client_line:
                connections += 1

        # Latency min/avg/max: -10/0/20007
        _, value = buf.readline().split(':')
        l_min, l_avg, l_max = [int(float(v)) for v in value.strip().split('/')]
        metrics.append(('zookeeper.min_latency_sec', float(l_min) / 1000))
        metrics.append(('zookeeper.avg_latency_sec', float(l_avg) / 1000))
        metrics.append(('zookeeper.max_latency_sec', float(l_max) / 1000))

        # Received: 101032173
        _, value = buf.readline().split(':')
        metrics.append(('zookeeper.in_bytes', int(value.strip())))

        # Sent: 1324
        _, value = buf.readline().split(':')
        metrics.append(('zookeeper.out_bytes', int(value.strip())))

        if has_connections_val:
            # Connections: 1
            _, value = buf.readline().split(':')
            metrics.append(('zookeeper.connections_count', int(value.strip())))
        else:
            # If the zk version doesn't explicitly give the Connections val,
            # use the value we computed from the client list.
            metrics.append(('zookeeper.connections_count', connections))

        # Outstanding: 0
        _, value = buf.readline().split(':')
        metrics.append(('zookeeper.outstanding_bytes', int(value.strip())))

        # Zxid: 0x1034799c7
        _, value = buf.readline().split(':')
        # Parse as a 64 bit hex int
        zxid = int(value.strip(), 16)
        # convert to bytes
        zxid_bytes = struct.pack('>q', zxid)
        # the higher order 4 bytes is the epoch
        (zxid_epoch,) = struct.unpack('>i', zxid_bytes[0:4])
        # the lower order 4 bytes is the count
        (zxid_count,) = struct.unpack('>i', zxid_bytes[4:8])

        metrics.append(('zookeeper.zxid_epoch', zxid_epoch))
        metrics.append(('zookeeper.zxid_count', zxid_count))

        # Mode: leader
        _, value = buf.readline().split(':')
        dimensions = {u'mode': value.strip().lower()}

        # Node count: 487
        _, value = buf.readline().split(':')
        metrics.append(('zookeeper.node_count', int(value.strip())))

        return metrics, dimensions
