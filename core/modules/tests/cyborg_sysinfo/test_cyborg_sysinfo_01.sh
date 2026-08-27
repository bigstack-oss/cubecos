#
# TEST - the passthrough filter in cyborg's nvidia sysinfo driver (#1262),
#        against the patch as it will be applied to cyborg 12.0.0 (#633)
#
#   1. a card hex recorded as "pgpu" is reported, matched across hex's
#      8-digit upper-case PCI address and lspci's 4-digit lower-case one
#   2. a card carved into sriovVgpu / migBackedVgpu is not reported
#   3. a virtual function is not reported even when the truth file calls it
#      pgpu -- the physfn check runs first
#   4. an unreadable, malformed or empty truth file reports nothing at all,
#      and does so before lspci is ever run (fail closed)
#
# Self-contained, and deliberately so: this drives the *patch file in this
# repo*, not an installed cyborg, so it needs no venv, no cyborg, no oslo, no
# GPU and no NVIDIA driver. Every cyborg/oslo module sysinfo.py imports is
# stubbed, and the three upstream helpers the discovery loop calls around the
# filter (_get_supported_vgpu_types, _get_traits, _generate_driver_device) are
# replaced after import, so what runs is exactly the filter and nothing else.
#
# Two things are copied rather than imported, both from
# cyborg/accelerator/drivers/gpu/utils.py at tag 12.0.0: GPU_FLAGS and
# GPU_INFO_PATTERN. They are the inputs the filter is fed, not part of it. If
# upstream changes that regex, this test keeps passing while the real driver
# changes behaviour -- so the copy is pinned to a version in the comment above
# it, the same way core/sdk_sh/tests/test_gpu_vgpu_profile_probe.sh pins the
# constants it copies out of sdk_gpu.sh.
#
#   Run by `make test`, or by hand: bash test_cyborg_sysinfo_01.sh
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

# TOP_SRCDIR is exported by the hex build (hex/make/hex_sdk_definitions.mk). The
# fallback is for a by-hand run from the source directory, which is four levels
# down from the top.
TOP="${TOP_SRCDIR:-$DIR/../../../..}"
SYSINFO="$TOP/core/cyborg/caracal_patch/accelerator/drivers/gpu/nvidia/sysinfo.py"

if [ ! -f "$SYSINFO" ]; then
    echo "FAIL: cannot find the patch under test at $SYSINFO"
    exit 1
fi

command -v python3 >/dev/null || { echo "FAIL: python3 not found"; exit 1; }

SYSINFO="$SYSINFO" python3 - <<'PYEOF'
import importlib.util
import json
import os
import re
import sys
import tempfile
import types

SRC = os.environ["SYSINFO"]

# ---------------------------------------------------------------- stubs ----
def stub(path, **attrs):
    m = types.ModuleType(path)
    for k, v in attrs.items():
        setattr(m, k, v)
    sys.modules[path] = m
    if '.' in path:
        parent, _, leaf = path.rpartition('.')
        setattr(sys.modules[parent], leaf, m)
    return m


class Logged(object):
    """Collects what the driver would have sent to the journal."""

    def __init__(self):
        self.records = []

    def _rec(self, level):
        def log(msg, *args):
            self.records.append((level, msg % args if args else msg))
        return log

    def __getattr__(self, level):
        return self._rec(level)

    def text(self):
        return "\n".join(m for _, m in self.records)


LOG = Logged()
stub('oslo_log', log=types.SimpleNamespace(getLogger=lambda name: LOG))
stub('oslo_serialization', jsonutils=types.SimpleNamespace(loads=json.loads))

# privsep's entrypoint decorator has to hand the function back unchanged: the
# driver calls the decorated function directly and expects its return value.
stub('cyborg')
stub('cyborg.privsep',
     sys_admin_pctxt=types.SimpleNamespace(entrypoint=lambda f: f))
stub('cyborg.conf',
     CONF=types.SimpleNamespace(host='test-host'),
     devices=types.SimpleNamespace(register_dynamic_opts=lambda conf: None))
stub('cyborg.accelerator')
stub('cyborg.accelerator.common')
stub('cyborg.accelerator.common.utils')
stub('cyborg.accelerator.drivers')
stub('cyborg.accelerator.drivers.gpu')

# GPU_FLAGS and GPU_INFO_PATTERN copied verbatim from
# cyborg/accelerator/drivers/gpu/utils.py at tag 12.0.0.
GPU_FLAGS = ["VGA compatible controller", "3D controller"]
GPU_INFO_PATTERN = re.compile(r"(?P<devices>[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:"
                              r"[0-9a-fA-F]{2}\.[0-9a-fA-F]) "
                              r"(?P<controller>.*) [\[].*]: (?P<model>.*) .*"
                              r"[\[](?P<vendor_id>[0-9a-fA-F]"
                              r"{4}):(?P<product_id>[0-9a-fA-F]{4})].*")

LSPCI_CALLS = []


def get_pci_devices(flags, vendor_id=None):
    LSPCI_CALLS.append((tuple(flags), vendor_id))
    return LSPCI_LINES


stub('cyborg.accelerator.drivers.gpu.utils',
     GPU_FLAGS=GPU_FLAGS,
     GPU_INFO_PATTERN=GPU_INFO_PATTERN,
     get_pci_devices=get_pci_devices)
stub('cyborg.common')
stub('cyborg.common.constants',
     RESOURCES={"PGPU": "PGPU", "VGPU": "VGPU"})
stub('cyborg.common.exception',
     InvalidVGPUType=type('InvalidVGPUType', (Exception,), {}))
stub('cyborg.objects')
stub('cyborg.objects.driver_objects')
for name in ('driver_attach_handle', 'driver_attribute',
             'driver_controlpath_id', 'driver_deployable', 'driver_device'):
    stub('cyborg.objects.driver_objects.' + name)

# --------------------------------------------------------------- fixture ----
TMP = tempfile.mkdtemp(prefix='cyborg-sysinfo-test-')
SYSFS = os.path.join(TMP, 'devices')
CONFIG = os.path.join(TMP, 'config.json')

PGPU = "0000:c8:00.0"        # hex records it as pgpu, a physical function
CARVED = "0001:41:00.0"      # hex records it as sriovVgpu
MIG = "0000:1f:00.0"         # hex records it as migBackedVgpu
VF = "0000:c8:01.1"          # recorded as pgpu, but sysfs says it is a VF
UNKNOWN = "0000:af:00.0"     # lspci sees it, hex has never heard of it

for addr in (PGPU, CARVED, MIG, VF, UNKNOWN):
    os.makedirs(os.path.join(SYSFS, addr))
# a VF is a VF because it carries a physfn link back to its PF
os.symlink(os.path.join(SYSFS, PGPU), os.path.join(SYSFS, VF, 'physfn'))


def lspci(addr, controller="3D controller"):
    return ("%s %s [0302]: NVIDIA Corporation GB202 [10de:2bb1] (rev a1)"
            % (addr, controller))


LSPCI_LINES = [lspci(a) for a in (PGPU, CARVED, MIG, VF, UNKNOWN)]

# hex writes an 8-digit domain in upper case; lspci prints four in lower case
HEX_ENTRIES = [
    {"id": "GPU-pf", "pciAddress": "00000000:C8:00.0", "type": "pgpu"},
    {"id": "GPU-sriov", "pciAddress": "00000001:41:00.0", "type": "sriovVgpu"},
    {"id": "GPU-mig", "pciAddress": "00000000:1F:00.0", "type": "migBackedVgpu"},
    {"id": "GPU-vf", "pciAddress": "00000000:C8:01.1", "type": "pgpu"},
]

# ------------------------------------------------------------------ load ----
spec = importlib.util.spec_from_file_location("cube_cyborg_sysinfo", SRC)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

mod.HEX_GPU_CONFIG_FILE = CONFIG
mod.SYS_PCI_DEVICES = SYSFS

# Replace the upstream helpers the discovery loop calls around the filter, so
# that what this exercises is the filter and the address matching only.
mod._get_supported_vgpu_types = lambda: ({}, {})
mod._get_traits = lambda *a, **k: {}
mod._generate_driver_device = lambda gpu_dict: gpu_dict

pass_ = 0
fail = 0


def ck(got, want, what):
    global pass_, fail
    if got == want:
        pass_ += 1
    else:
        fail += 1
        print("FAIL: %s -> got %r want %r" % (what, got, want))


def write_config(payload, raw=None):
    with open(CONFIG, 'w') as f:
        f.write(raw if raw is not None else json.dumps(payload))


def discover():
    del LSPCI_CALLS[:]
    LOG.records = []
    return [d["devices"] for d in mod._discover_gpus("10de")]


# ---- 0. the copied regex still matches the lspci form fed to the filter ----
ck(bool(GPU_INFO_PATTERN.match(lspci(PGPU))), True,
   "case 0: the copied GPU_INFO_PATTERN matches the fixture lspci line")
print("  ok  copied lspci regex matches fixture")

# ---- 1./2./3. the filter itself -------------------------------------------
write_config(HEX_ENTRIES)
reported = discover()
ck(reported, [PGPU], "case 1: only the pgpu physical function is reported")
print("  ok  pgpu reported, address normalised across hex/lspci spelling")
ck(CARVED in reported, False, "case 2: an sriovVgpu card must not be reported")
ck(MIG in reported, False,
   "case 2: a migBackedVgpu card must not be reported")
print("  ok  sriovVgpu and migBackedVgpu cards withheld")
ck(VF in reported, False,
   "case 3: a virtual function must not be reported even when recorded pgpu")
print("  ok  virtual function withheld despite a pgpu record")
ck(UNKNOWN in reported, False,
   "case 3b: a card absent from the truth file must not be reported")
print("  ok  card absent from the truth file withheld")

# ---- 4. fail closed, before lspci -----------------------------------------
os.unlink(CONFIG)
ck(discover(), [], "case 4a: a missing truth file reports nothing")
ck(len(LSPCI_CALLS), 0,
   "case 4a: lspci must not run once the truth file cannot be read")
ck("cannot read" in LOG.text(), True,
   "case 4a: the refusal has to say why")
print("  ok  missing truth file      -> nothing reported, lspci not run")

write_config(None, raw="{not json at all")
ck(discover(), [], "case 4b: a malformed truth file reports nothing")
ck(len(LSPCI_CALLS), 0, "case 4b: lspci must not run on malformed input")
ck("not valid JSON" in LOG.text(), True,
   "case 4b: the refusal has to name the parse failure")
print("  ok  malformed truth file    -> nothing reported, lspci not run")

write_config({"cards": []})
ck(discover(), [], "case 4c: a JSON object instead of an array reports nothing")
ck("not a JSON array" in LOG.text(), True,
   "case 4c: the refusal has to name the shape")
print("  ok  JSON object not array   -> nothing reported")

write_config([])
ck(discover(), [], "case 4d: an empty array reports nothing")
ck(len(LSPCI_CALLS), 0, "case 4d: lspci must not run with nothing to report")
print("  ok  empty truth file        -> nothing reported, lspci not run")

# ---- 5. address normalisation, directly ------------------------------------
ck(mod._normalize_pci_address("00000000:C8:00.0"), "0000:c8:00.0",
   "case 5: 8-digit upper-case hex form")
ck(mod._normalize_pci_address("0001:41:00.0"), "0001:41:00.0",
   "case 5: already-lspci form is unchanged")
ck(mod._normalize_pci_address(" 00010000:AF:00.1 "), "10000:af:00.1",
   "case 5: a domain wider than 4 digits keeps its digits")
ck(mod._normalize_pci_address("not-an-address"), "not-an-address",
   "case 5: an unparseable value is passed through lower-cased")
ck(mod._normalize_pci_address("ZZZZ:c8:00.0"), "zzzz:c8:00.0",
   "case 5: a non-hex domain is passed through rather than raising")
print("  ok  address normalisation")

import shutil
shutil.rmtree(TMP, ignore_errors=True)

if fail:
    print("cyborg_sysinfo: %d assertion(s) failed" % fail)
    sys.exit(1)
print("cyborg_sysinfo: passthrough filter passed all %d assertions" % pass_)
PYEOF
