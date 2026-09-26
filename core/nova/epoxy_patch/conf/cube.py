# Cube downstream: live-resize (vCPU/memory hot-add) options.

from oslo_config import cfg

cube_group = cfg.OptGroup(
    'cube',
    title='Cube downstream options',
    help="Options for CubeCOS downstream features.")

live_resize_opts = [
    cfg.BoolOpt(
        'live_resize_default_headroom',
        default=True,
        help="Boot every eligible instance with hotplug headroom "
             "(maxMemory + vcpu ceiling) so it can be live-resized. "
             "hw:max_vcpus/hw:max_memory_mb flavor extra specs override "
             "the computed ceiling per flavor (0 opts a flavor out)."),
    cfg.IntOpt(
        'live_resize_headroom_factor',
        default=4,
        min=1,
        help="Default hotplug ceiling as a multiple of the flavor's "
             "vCPUs and memory."),
    cfg.IntOpt(
        'live_resize_max_vcpus',
        default=32,
        min=1,
        help="Absolute cap on the default vCPU hotplug ceiling."),
    cfg.IntOpt(
        'live_resize_max_memory_mb',
        default=131072,
        min=1,
        help="Absolute cap on the default memory hotplug ceiling (MB)."),
    cfg.IntOpt(
        'live_resize_migrate_timeout',
        default=1800,
        min=60,
        help="Seconds to wait for the live migration performed when a "
             "live resize does not fit on the instance's current host."),
]


def register_opts(conf):
    conf.register_group(cube_group)
    conf.register_opts(live_resize_opts, group=cube_group)


def list_opts():
    return {cube_group: live_resize_opts}
