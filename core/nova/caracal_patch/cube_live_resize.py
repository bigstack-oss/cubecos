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


# key in instance.system_metadata carrying the in-flight target flavor id
# while a live resize is migrating the instance to a host that fits
SYSMETA_FLAVOR_ID = "cube_live_resize_flavor_id"

# Ceiling actually baked into the running domain, recorded at spawn so the API
# can answer a resize plan from the instance object -- no compute RPC. The
# config default is only a fallback for instances booted before this shipped.
SYSMETA_MAX_VCPUS = "cube_live_resize_max_vcpus"
SYSMETA_MAX_MEM_MB = "cube_live_resize_max_memory_mb"


def record_headroom(instance, max_vcpus, max_mem_mb):
    """Stash the domain's real ceiling on the instance at domain-build time."""
    instance.system_metadata[SYSMETA_MAX_VCPUS] = str(max_vcpus)
    instance.system_metadata[SYSMETA_MAX_MEM_MB] = str(max_mem_mb)


def recorded_headroom(instance):
    """The recorded ceiling, or None when the instance predates the record.

    Callers fall back to headroom(instance.flavor); that is the config-derived
    estimate and can be wrong when the flavor carried an extra-spec override,
    which is exactly why the recorded value exists.
    """
    sysmeta = instance.system_metadata
    if SYSMETA_MAX_VCPUS not in sysmeta or SYSMETA_MAX_MEM_MB not in sysmeta:
        return None
    try:
        return (int(sysmeta[SYSMETA_MAX_VCPUS]), int(sysmeta[SYSMETA_MAX_MEM_MB]))
    except (TypeError, ValueError):
        return None


def set_allocations(reportclient, context, consumer_uuid, flavor,
                    vcpus=None, memory_mb=None):
    """PUT the consumer's allocations resized to flavor.

    vcpus/memory_mb override the flavor values (used to claim only the
    CPU half on the source before an auto-migrate).
    Returns False when placement rejects the new size (no capacity).
    """
    allocs = reportclient.get_allocs_for_consumer(context, consumer_uuid)
    if not allocs.get("allocations"):
        return False
    for alloc in allocs["allocations"].values():
        res = alloc["resources"]
        if "VCPU" in res:
            res["VCPU"] = vcpus if vcpus is not None else flavor.vcpus
        if "MEMORY_MB" in res:
            res["MEMORY_MB"] = (memory_mb if memory_mb is not None
                                else flavor.memory_mb)
    return reportclient.put_allocations(context, consumer_uuid, allocs)
