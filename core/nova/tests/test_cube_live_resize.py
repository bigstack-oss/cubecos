# Unit tests for the cube live-resize helpers.
#
# Deliberately outside core/nova/caracal_patch/: nova.mk installs everything in
# the patch dir verbatim onto the rootfs, so tests placed there would ship to
# every node.
#
# Run against a node's caracal venv (nova already importable):
#   /opt/openstack-caracal/bin/python -m unittest discover -s . -p 'test_*.py' -v

import unittest

from nova import cube_live_resize as clr

CONF = clr.CONF


class FakeFlavor(object):
    def __init__(self, vcpus=2, memory_mb=4096, extra_specs=None):
        self.vcpus = vcpus
        self.memory_mb = memory_mb
        self.extra_specs = extra_specs or {}


class FakeInstance(object):
    def __init__(self, system_metadata=None):
        self.system_metadata = system_metadata if system_metadata is not None else {}


class TestBlocked(unittest.TestCase):
    def test_plain_flavor_is_not_blocked(self):
        self.assertIsNone(clr.blocked(FakeFlavor()))

    def test_numa_nodes_blocks(self):
        f = FakeFlavor(extra_specs={'hw:numa_nodes': '2'})
        self.assertEqual('hw:numa_nodes', clr.blocked(f))

    def test_mem_page_size_blocks(self):
        f = FakeFlavor(extra_specs={'hw:mem_page_size': 'large'})
        self.assertEqual('hw:mem_page_size', clr.blocked(f))

    def test_dedicated_cpu_policy_blocks(self):
        f = FakeFlavor(extra_specs={'hw:cpu_policy': 'dedicated'})
        self.assertEqual('hw:cpu_policy=dedicated', clr.blocked(f))

    def test_shared_cpu_policy_does_not_block(self):
        f = FakeFlavor(extra_specs={'hw:cpu_policy': 'shared'})
        self.assertIsNone(clr.blocked(f))


class TestHeadroom(unittest.TestCase):
    def setUp(self):
        super(TestHeadroom, self).setUp()
        CONF.set_override('live_resize_default_headroom', True, group='cube')
        CONF.set_override('live_resize_headroom_factor', 4, group='cube')
        CONF.set_override('live_resize_max_vcpus', 32, group='cube')
        CONF.set_override('live_resize_max_memory_mb', 131072, group='cube')
        self.addCleanup(CONF.clear_override,
                        'live_resize_default_headroom', group='cube')
        self.addCleanup(CONF.clear_override,
                        'live_resize_headroom_factor', group='cube')
        self.addCleanup(CONF.clear_override,
                        'live_resize_max_vcpus', group='cube')
        self.addCleanup(CONF.clear_override,
                        'live_resize_max_memory_mb', group='cube')

    def test_default_is_the_configured_multiple(self):
        self.assertEqual((8, 16384), clr.headroom(FakeFlavor(2, 4096)))

    def test_absolute_caps_bound_the_default(self):
        # 16 vCPU * 4 = 64 -> capped at 32; 65536 * 4 = 262144 -> capped
        self.assertEqual((32, 131072), clr.headroom(FakeFlavor(16, 65536)))

    def test_extra_spec_override_wins_over_the_default(self):
        f = FakeFlavor(2, 4096, {'hw:max_vcpus': '6', 'hw:max_memory_mb': '8192'})
        self.assertEqual((6, 8192), clr.headroom(f))

    def test_override_may_exceed_the_config_caps(self):
        # the override branch is not clamped by live_resize_max_*
        f = FakeFlavor(2, 4096, {'hw:max_vcpus': '64',
                                 'hw:max_memory_mb': '393216'})
        self.assertEqual((64, 393216), clr.headroom(f))

    def test_zero_override_opts_the_flavor_out(self):
        f = FakeFlavor(2, 4096, {'hw:max_vcpus': '0', 'hw:max_memory_mb': '0'})
        self.assertEqual((0, 0), clr.headroom(f))

    def test_one_sided_override_zeroes_the_unset_half(self):
        # only memory is overridden; the vCPU half defaults to 0 and is then
        # rejected for being below the flavor, so CPU growth is refused
        f = FakeFlavor(2, 4096, {'hw:max_memory_mb': '8192'})
        self.assertEqual((0, 8192), clr.headroom(f))

    def test_ceiling_below_the_flavor_is_treated_as_no_headroom(self):
        f = FakeFlavor(8, 8192, {'hw:max_vcpus': '4', 'hw:max_memory_mb': '4096'})
        self.assertEqual((0, 0), clr.headroom(f))

    def test_blocked_flavor_gets_no_headroom(self):
        f = FakeFlavor(2, 4096, {'hw:numa_nodes': '2'})
        self.assertEqual((0, 0), clr.headroom(f))

    def test_headroom_disabled_by_config(self):
        CONF.set_override('live_resize_default_headroom', False, group='cube')
        self.assertEqual((0, 0), clr.headroom(FakeFlavor(2, 4096)))

    def test_garbage_override_is_not_trusted(self):
        f = FakeFlavor(2, 4096, {'hw:max_vcpus': 'lots'})
        self.assertEqual((0, 0), clr.headroom(f))


class TestRecordedHeadroom(unittest.TestCase):
    def test_round_trip(self):
        inst = FakeInstance()
        clr.record_headroom(inst, 8, 16384)
        self.assertEqual((8, 16384), clr.recorded_headroom(inst))

    def test_values_are_stored_as_strings(self):
        # system_metadata is a string->string map; ints would not survive
        inst = FakeInstance()
        clr.record_headroom(inst, 8, 16384)
        for v in inst.system_metadata.values():
            self.assertIsInstance(v, str)

    def test_absent_record_returns_none(self):
        # an instance booted before the ceiling was recorded
        self.assertIsNone(clr.recorded_headroom(FakeInstance()))

    def test_half_written_record_returns_none(self):
        inst = FakeInstance({clr.SYSMETA_MAX_VCPUS: '8'})
        self.assertIsNone(clr.recorded_headroom(inst))

    def test_corrupt_record_returns_none_rather_than_raising(self):
        # a caller falling back to the estimate is recoverable; a 500 is not
        inst = FakeInstance({clr.SYSMETA_MAX_VCPUS: 'eight',
                             clr.SYSMETA_MAX_MEM_MB: '16384'})
        self.assertIsNone(clr.recorded_headroom(inst))

    def test_zero_ceiling_is_recorded_not_mistaken_for_absent(self):
        # an opted-out instance genuinely has a 0/0 ceiling; that must be
        # reported as exact, not fall back to the config estimate
        inst = FakeInstance()
        clr.record_headroom(inst, 0, 0)
        self.assertEqual((0, 0), clr.recorded_headroom(inst))


if __name__ == '__main__':
    unittest.main()


class FakeAlloc(object):
    """Minimal report client: records what was PUT back to placement."""

    def __init__(self, resources):
        self.allocs = {"allocations": {"rp": {"resources": dict(resources)}}}
        self.put = None

    def get_allocs_for_consumer(self, context, uuid):
        return self.allocs

    def put_allocations(self, context, uuid, allocs):
        self.put = allocs["allocations"]["rp"]["resources"]
        return True


class TestSetAllocationsDisk(unittest.TestCase):
    """DISK_GB moves only when a caller asks, because only an image-backed
    root is grown by the compute. A boot-from-volume root is cinder's, and
    claiming host disk for it would double-count."""

    def _run(self, resources, **kwargs):
        rc = FakeAlloc(resources)
        clr.set_allocations(rc, None, "uuid",
                            FakeFlavor(vcpus=4, memory_mb=8192), **kwargs)
        return rc.put

    def test_disk_untouched_when_root_gb_not_passed(self):
        put = self._run({"VCPU": 2, "MEMORY_MB": 4096, "DISK_GB": 20})
        self.assertEqual(20, put["DISK_GB"])
        self.assertEqual(4, put["VCPU"])
        self.assertEqual(8192, put["MEMORY_MB"])

    def test_disk_claimed_when_root_gb_passed(self):
        put = self._run({"VCPU": 2, "MEMORY_MB": 4096, "DISK_GB": 20},
                        root_gb=40)
        self.assertEqual(40, put["DISK_GB"])

    def test_disk_absent_from_allocation_is_not_invented(self):
        # a boot-from-volume consumer has no DISK_GB on the compute's provider
        put = self._run({"VCPU": 2, "MEMORY_MB": 4096}, root_gb=40)
        self.assertNotIn("DISK_GB", put)

    def test_cpu_only_claim_still_leaves_disk_alone(self):
        # the source-side vCPU grow before an auto-migrate
        put = self._run({"VCPU": 2, "MEMORY_MB": 4096, "DISK_GB": 20},
                        memory_mb=4096)
        self.assertEqual(4, put["VCPU"])
        self.assertEqual(4096, put["MEMORY_MB"])
        self.assertEqual(20, put["DISK_GB"])
