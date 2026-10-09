"""Check the cluster has what the selected suite needs. Exit 3 on any FAIL."""
import ipaddress
import json
import os
import subprocess
import sys

import openstack

PLUGIN_SERVICE = {"neutron": "network", "cinder": "volumev3", "octavia": "load-balancer", "designate": "dns",
                  "heat": "orchestration", "manila": "sharev2", "barbican": "key-manager",
                  "watcher": "infra-optim", "cyborg": "accelerator", "ironic": "baremetal"}
# free floating IPs per suite (routers + scenario servers; full runs plugin groups one by one)
MIN_FIPS = {"smoke": 5, "regex": 5, "api": 10, "scenario": 10, "full": 20}
MIN_QUOTA = {"instances": 10, "cores": 20, "ram": 20480, "volumes": 10, "gigabytes": 100}
MIN_VCPU, MIN_RAM_MB, MIN_VOL_GB = 4, 4096, 20

suite = "regex" if os.environ.get("REGEX") else os.environ.get("SUITE", "smoke")
plugins = list(PLUGIN_SERVICE) if suite == "full" else [suite] if suite in PLUGIN_SERVICE else []
fails = 0


def report(ok, what, detail="", warn=False):
    global fails
    tag = "OK  " if ok else "WARN" if warn else "FAIL"
    fails += not ok and not warn
    print(f"preflight {tag} {what}{': ' + detail if detail else ''}", flush=True)


def cli(*args):
    return json.loads(subprocess.run(["openstack", *args, "-f", "json"], check=True,
                                     capture_output=True, text=True).stdout)


conn = openstack.connect()

# services the suite talks to
types = {e["type"] for e in conn.service_catalog}
need = {"identity", "compute", "network", "image", "volumev3"} | {PLUGIN_SERVICE[p] for p in plugins if p != "ironic"}
missing = sorted(need - types)
report(not missing, "catalog", f"missing {' '.join(missing)}" if missing else f"{len(need)} services")

# compute: an up nova-compute and free capacity in placement
up = [s for s in conn.compute.services(binary="nova-compute") if s.state == "up" and s.status == "enabled"]
report(bool(up), "nova-compute up", f"{len(up)} host(s)")
free = {"VCPU": 0, "MEMORY_MB": 0}
for rp in conn.placement.resource_providers():
    usage = conn.placement.get(f"/resource_providers/{rp.id}/usages").json()["usages"]
    for inv in conn.placement.resource_provider_inventories(rp):
        if inv.resource_class in free:
            cap = (inv.total - inv.reserved) * inv.allocation_ratio
            free[inv.resource_class] += max(0, int(cap - usage.get(inv.resource_class, 0)))
report(free["VCPU"] >= MIN_VCPU, "free vCPU (placement)", f"{free['VCPU']} (need {MIN_VCPU})")
report(free["MEMORY_MB"] >= MIN_RAM_MB, "free RAM (placement)", f"{free['MEMORY_MB']} MB (need {MIN_RAM_MB})")

# block storage: an up backend with room, and the volume type tempest.conf names
vol_up = [s for s in conn.block_storage.services() if s.binary == "cinder-volume" and s.state == "up"]
report(bool(vol_up), "cinder-volume up", f"{len(vol_up)} backend(s)")
vol_free = max([p.capabilities.get("free_capacity_gb", 0) for p in conn.block_storage.backend_pools()] or [0])
report(vol_free >= MIN_VOL_GB, "volume backend free", f"{vol_free:.0f} GB (need {MIN_VOL_GB})")
report(conn.block_storage.find_type("CubeStorage") is not None, "volume type CubeStorage")

# public network: free addresses in the external subnets' allocation pools
need_fips = int(os.environ.get("MIN_FIPS") or MIN_FIPS.get(suite, 10))
ext = list(conn.network.networks(is_router_external=True))
pool_free = 0
for net in ext:
    used = {ip["ip_address"] for p in conn.network.ports(network_id=net.id) for ip in p.fixed_ips}
    for sub in conn.network.subnets(network_id=net.id):
        for pool in sub.allocation_pools or []:
            lo, hi = ipaddress.ip_address(pool["start"]), ipaddress.ip_address(pool["end"])
            pool_free += int(hi) - int(lo) + 1 - sum(lo <= ipaddress.ip_address(a) <= hi for a in used)
report(bool(ext), "external network", ", ".join(n.name for n in ext) or "none")
report(pool_free >= need_fips, "free floating IPs", f"{pool_free} (need {need_fips}; MIN_FIPS= overrides)")
dead = [f"{a.agent_type}@{a.host}" for a in conn.network.agents() if not a.is_alive]
report(not dead, "network agents", f"down: {' '.join(dead)}" if dead else "all alive", warn=True)

# default quotas: tempest's dynamic projects get these
limits = {q["Resource"]: q["Limit"] for q in cli("quota", "show", "--default")}
low = [f"{k}={limits[k]}<{v}" for k, v in MIN_QUOTA.items() if k in limits and -1 < limits[k] < v]
report(not low, "default quotas", " ".join(low) or "ok")

# images and types the plugin suites rely on
if "octavia" in plugins:
    amp = [i for i in conn.image.images(tag="amphora") if i.status == "active"]
    report(bool(amp), "amphora image (tag amphora)", ", ".join(i.name for i in amp) or "none imported")
if "manila" in plugins:
    img = conn.image.find_image("manila-service-image")
    report(img is not None and img.status == "active", "manila-service-image", img.status if img else "not imported")
    names = {t["Name"] for t in cli("share", "type", "list")}
    report("tenant_share_type" in names, "share type tenant_share_type")

# leftovers from another (or a crashed) run; two runs at once break each other's teardown
left = [p.name for p in conn.identity.projects() if p.name.startswith("tempest-")]
report(not left, "no tempest-* projects", f"{len(left)} found: another run active, or clean up first" if left else "",
       warn=True)

print(f"preflight: {'FAILED' if fails else 'passed'} ({suite})")
sys.exit(3 if fails else 0)
