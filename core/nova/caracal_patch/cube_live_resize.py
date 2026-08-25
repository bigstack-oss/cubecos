# Cube downstream: live-resize policy helpers, shared by the API,
# conductor, and libvirt driver layers (no libvirt imports here).

import nova.conf

CONF = nova.conf.CONF

MAX_VCPUS_SPEC = "hw:max_vcpus"
MAX_MEM_SPEC = "hw:max_memory_mb"
MEM_SLOTS = 8
_BLOCKING_SPECS = ("hw:numa_nodes", "hw:mem_page_size")


def blocked(flavor):
    """Reason this flavor cannot carry hotplug headroom, or None."""
    for spec in _BLOCKING_SPECS:
        if flavor.extra_specs.get(spec):
            return spec
    if flavor.extra_specs.get("hw:cpu_policy") == "dedicated":
        return "hw:cpu_policy=dedicated"
    return None


def headroom(flavor):
    """The hotplug ceiling (max_vcpus, max_memory_mb) for this flavor.

    Extra-spec override wins (0 opts out); otherwise the config default
    applies; (0, 0) means not live-resizable.
    """
    if blocked(flavor):
        return (0, 0)
    specs = flavor.extra_specs
    if MAX_VCPUS_SPEC in specs or MAX_MEM_SPEC in specs:
        try:
            max_vcpus = int(specs.get(MAX_VCPUS_SPEC, 0))
            max_mem = int(specs.get(MAX_MEM_SPEC, 0))
        except (TypeError, ValueError):
            return (0, 0)
    elif CONF.cube.live_resize_default_headroom:
        factor = CONF.cube.live_resize_headroom_factor
        max_vcpus = min(flavor.vcpus * factor,
                        CONF.cube.live_resize_max_vcpus)
        max_mem = min(flavor.memory_mb * factor,
                      CONF.cube.live_resize_max_memory_mb)
    else:
        return (0, 0)
    if max_vcpus < flavor.vcpus:
        max_vcpus = 0
    if max_mem < flavor.memory_mb:
        max_mem = 0
    return (max_vcpus, max_mem)
