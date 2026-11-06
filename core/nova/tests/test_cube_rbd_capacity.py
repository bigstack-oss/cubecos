# Unit tests for the cube RBD capacity helper.
#
# Kept outside epoxy_patch/: nova.mk installs that directory onto every node.
# Run against a node's epoxy venv (nova already importable):
#   /opt/openstack-epoxy/bin/python -m unittest discover -s . -p 'test_*.py' -v

import unittest
from unittest import mock

from nova import cube_rbd_capacity as crc


@mock.patch('nova.cube_rbd_capacity.processutils.execute')
class TestOsdCapacityBytes(unittest.TestCase):
    def test_sums_all_osds(self, execute):
        execute.return_value = (
            '[{"id": 0, "bluestore_bdev_size": "100"}, '
            '{"id": 1, "bluestore_bdev_size": "200"}]', '')
        self.assertEqual(300, crc.osd_capacity_bytes([], 100))

    def test_never_below_fallback(self, execute):
        execute.return_value = (
            '[{"id": 0, "bluestore_bdev_size": "100"}]', '')
        self.assertEqual(500, crc.osd_capacity_bytes([], 500))

    def test_command_failure_returns_fallback(self, execute):
        execute.side_effect = crc.processutils.ProcessExecutionError()
        self.assertEqual(500, crc.osd_capacity_bytes([], 500))

    def test_malformed_json_returns_fallback(self, execute):
        execute.return_value = ('not json', '')
        self.assertEqual(500, crc.osd_capacity_bytes([], 500))

    def test_missing_size_returns_fallback(self, execute):
        execute.return_value = (
            '[{"id": 0, "bluestore_bdev_size": "1000"}, {"id": 1}]', '')
        self.assertEqual(500, crc.osd_capacity_bytes([], 500))

    def test_empty_or_zero_sum_returns_fallback(self, execute):
        for out in ('[]', '[{"id": 0, "bluestore_bdev_size": "0"}]'):
            with self.subTest(out=out):
                execute.return_value = (out, '')
                with mock.patch.object(crc.LOG, 'warning') as warning:
                    self.assertEqual(500, crc.osd_capacity_bytes([], 500))
                warning.assert_called_once()

    def test_invalid_size_returns_fallback(self, execute):
        for size in ('"invalid"', 'null'):
            with self.subTest(size=size):
                execute.return_value = (
                    '[{"id": 0, "bluestore_bdev_size": %s}]' % size, '')
                self.assertEqual(500, crc.osd_capacity_bytes([], 500))

    def test_ceph_args_passed_through(self, execute):
        execute.return_value = (
            '[{"id": 0, "bluestore_bdev_size": "100"}]', '')
        crc.osd_capacity_bytes(
            ['--id', 'nova', '--conf', '/etc/ceph.conf'], 50)
        execute.assert_called_once_with(
            'ceph', 'osd', 'metadata', '--format=json',
            '--id', 'nova', '--conf', '/etc/ceph.conf')


if __name__ == '__main__':
    unittest.main()
