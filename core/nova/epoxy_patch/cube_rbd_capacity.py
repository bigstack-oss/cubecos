# Cube downstream: keep RBD capacity stable when OSDs are marked out.

from oslo_concurrency import processutils
from oslo_log import log as logging
from oslo_serialization import jsonutils

LOG = logging.getLogger(__name__)


def osd_capacity_bytes(ceph_args, fallback):
    """ceph df drops out OSDs; metadata keeps every OSD the cluster has."""
    try:
        out, _ = processutils.execute(
            'ceph', 'osd', 'metadata', '--format=json', *ceph_args)
        total = sum(int(osd['bluestore_bdev_size'])
                    for osd in jsonutils.loads(out))
        if total <= 0:
            raise ValueError('empty or zero OSD capacity')
        return max(total, fallback)
    except (processutils.ProcessExecutionError, ValueError, KeyError,
            TypeError) as exc:
        LOG.warning('Cannot read OSD capacity; using ceph df total: %s', exc)
        return fallback
