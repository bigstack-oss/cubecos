# Unit tests for the cube nova patches

These live here rather than in `core/nova/<release>_patch/` on purpose: `nova.mk`'s
`rootfs_install` installs **everything** in the patch dir that is not `*.patch` / `*.orig`
verbatim onto the rootfs, so a test file placed there would ship to every node.

## Running them

Against a node's caracal venv, where nova is already importable:

```bash
scp test_cube_live_resize.py root@<node>:/tmp/
ssh root@<node> 'cd /tmp && /opt/openstack-caracal/bin/python -m unittest test_cube_live_resize -v'
```

Or in a local venv built the way the port was verified:

```bash
python3.11 -m venv /tmp/nova-test && . /tmp/nova-test/bin/activate
pip install -c core/heavyfs/os-caracal-pip-upper-constraints.txt nova==29.4.0
# apply core/nova/caracal_patch over site-packages/nova, then run unittest
```

The constraints file matters: without it the venv picks up an oslo.utils / setuptools
newer than caracal expects and nova will not import.

`unittest` and `unittest.mock` are stdlib; the venv has neither pytest nor the standalone
`mock` package, so tests should not reach for them.
