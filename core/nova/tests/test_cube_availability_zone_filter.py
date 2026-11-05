# Unit tests for the Cube availability-zone host filter.
#
# Deliberately outside core/nova/epoxy_patch/: nova.mk installs everything in
# the patch dir verbatim onto the rootfs, so tests placed there would ship to
# every node.
#
# Run from core/nova/tests against a node's epoxy venv (nova importable and the
# downstream filter installed):
#   /opt/openstack-epoxy/bin/python -m unittest discover -s . -p 'test_cube_availability_zone_filter.py' -v

import unittest

from nova.scheduler import filters
from nova.scheduler.filters import cube_availability_zone_filter as cazf


class FakeAggregate:
    def __init__(self, metadata):
        self.metadata = metadata


class FakeHostState:
    def __init__(self, *metadata):
        self.aggregates = [FakeAggregate(item) for item in metadata]


class FakeSpec:
    def __init__(self, availability_zone):
        self.availability_zone = availability_zone


class TestCubeAvailabilityZoneFilter(unittest.TestCase):
    def setUp(self):
        super().setUp()
        cazf.CONF.set_override('default_availability_zone', 'nova')
        self.addCleanup(cazf.CONF.clear_override, 'default_availability_zone')
        self.host_filter = cazf.CubeAvailabilityZoneFilter()

    def test_no_requested_az_passes_any_host(self):
        for requested_az in (None, ''):
            for host in (FakeHostState(),
                         FakeHostState({'availability_zone': 'az1'}),
                         FakeHostState({'other_key': 'value'})):
                with self.subTest(requested_az=requested_az,
                                  aggregates=host.aggregates):
                    self.assertTrue(self.host_filter.host_passes(
                        host, FakeSpec(requested_az)))

    def test_default_az_passes_host_without_aggregates(self):
        self.assertTrue(self.host_filter.host_passes(
            FakeHostState(), FakeSpec('nova')))

    def test_default_az_rejects_host_in_named_az(self):
        self.assertFalse(self.host_filter.host_passes(
            FakeHostState({'availability_zone': 'az1'}), FakeSpec('nova')))

    def test_default_az_passes_aggregate_without_az_metadata(self):
        self.assertTrue(self.host_filter.host_passes(
            FakeHostState({'other_key': 'value'}), FakeSpec('nova')))

    def test_named_az_passes_host_in_that_az(self):
        self.assertTrue(self.host_filter.host_passes(
            FakeHostState({'availability_zone': 'az1'}), FakeSpec('az1')))

    def test_named_az_rejects_host_without_az(self):
        for host in (FakeHostState(), FakeHostState({'other_key': 'value'})):
            with self.subTest(aggregates=host.aggregates):
                self.assertFalse(self.host_filter.host_passes(
                    host, FakeSpec('az1')))

    def test_named_az_rejects_host_in_another_az(self):
        self.assertFalse(self.host_filter.host_passes(
            FakeHostState({'availability_zone': 'az1'}), FakeSpec('az2')))

    def test_az_name_with_comma_is_one_az(self):
        host = FakeHostState({'availability_zone': 'az1,az2'})
        self.assertTrue(self.host_filter.host_passes(host, FakeSpec('az1,az2')))
        self.assertFalse(self.host_filter.host_passes(host, FakeSpec('az2')))

    def test_az_metadata_from_multiple_aggregates(self):
        self.assertTrue(self.host_filter.host_passes(
            FakeHostState({'availability_zone': 'az1'},
                          {'availability_zone': 'az2'}), FakeSpec('az2')))

    def test_configured_default_az(self):
        cazf.CONF.set_override('default_availability_zone', 'other')
        # setUp's cleanup clears this override too.
        host = FakeHostState()
        self.assertTrue(self.host_filter.host_passes(host, FakeSpec('other')))
        self.assertFalse(self.host_filter.host_passes(host, FakeSpec('nova')))

    def test_does_not_run_on_rebuild(self):
        self.assertIs(False, self.host_filter.RUN_ON_REBUILD)

    def test_class_is_discoverable_by_name(self):
        classes = filters.HostFilterHandler().get_matching_classes(
            ['nova.scheduler.filters.all_filters'])
        self.assertIn('CubeAvailabilityZoneFilter',
                      [cls.__name__ for cls in classes])


if __name__ == '__main__':
    unittest.main()
