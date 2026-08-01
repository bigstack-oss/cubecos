# Monasca agent check: per-VM L3 cache occupancy via Intel RDT (pqos).
# Feeds Watcher noisy_neighbor (instance_l3_cache_usage, keyed by resource_id).
import re
import subprocess

import monasca_agent.collector.checks as checks

# a data row starts with the PID; the CORE column may be a number or "err"
# (a multi-vCPU process spans cores), so don't require a numeric core.
_LLC_ROW = re.compile(r'^\s*\d+\s+\S+\s')


class RdtL3(checks.AgentCheck):
    """Publish instance_l3_cache_usage (LLC, KB) per VM, dimension
    resource_id = instance uuid, read from `pqos` (intel-cmt-cat). Monitors one
    PID at a time (RDT has a limited number of RMIDs). Skips silently if pqos or
    RDT is unavailable.
    """

    def _vm_uuid(self, pid):
        try:
            with open('/proc/%s/cmdline' % pid, 'rb') as f:
                args = f.read().split(b'\0')
        except OSError:
            return None
        for i, a in enumerate(args):
            if a == b'-uuid' and i + 1 < len(args):
                return args[i + 1].decode(errors='ignore')
        return None

    def _llc_kb(self, pid):
        try:
            out = subprocess.check_output(
                ['sudo', '-n', 'pqos', '-I', '-p', 'llc:%s' % pid, '-t', '1'],
                timeout=10, stderr=subprocess.DEVNULL).decode()
        except (OSError, subprocess.SubprocessError):
            return None
        val = None
        for line in out.splitlines():
            if _LLC_ROW.match(line):
                val = line.split()[-1]   # LLC[KB] is the last column
        try:
            return float(val)
        except (TypeError, ValueError):
            return None

    def check(self, instance):
        try:
            pids = subprocess.check_output(
                ['pgrep', '-f', 'guest=instance'],
                stderr=subprocess.DEVNULL).decode().split()
        except (OSError, subprocess.SubprocessError):
            return
        for pid in pids:
            uuid = self._vm_uuid(pid)
            if not uuid:
                continue
            llc = self._llc_kb(pid)
            if llc is None:
                continue
            dimensions = self._set_dimensions({'resource_id': uuid}, instance)
            self.gauge('instance_l3_cache_usage', llc, dimensions=dimensions)
