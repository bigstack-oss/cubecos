# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

# Per-instance CPU and memory, written as a node_exporter textfile.
#
# These are the two metrics Watcher's prometheus datasource needs for the
# workload_balance strategy and the only ones nothing else in the stack produces --
# node_exporter covers the host half, and no packaged exporter covers the VM half.
# There is no libvirt exporter worth shipping: the upstream one has had no commit since
# June 2021 and prometheus-community declined to adopt it, which fails the same
# provenance test that rejected kafka_exporter.
#
# The names are Watcher's, not ours, and they are not negotiable. Its prometheus
# datasource hardcodes instance_cpu_usage -> ceilometer_cpu and instance_ram_usage ->
# ceilometer_memory_usage in METRIC_MAP, and _build_prometheus_query then dispatches on
# the meter name and raises "Cannot process prometheus meter" for anything it does not
# recognise. metric_map_path can rename the meter but that only breaks the dispatch, so
# emitting the ceilometer names is what keeps the backported datasource pristine -- and
# lets the patch be dropped entirely on Epoxy, which ships it.
#
# Units follow from Watcher's own arithmetic, so both are fixed:
#   ceilometer_cpu            counter, cumulative NANOSECONDS. Watcher computes
#                             clamp_max((rate(...)/10e+8) * (100/vcpus), 100), so seconds
#                             would read 1e9 times low and always clamp to nothing.
#   ceilometer_memory_usage   gauge, MEBIBYTES, read with avg_over_time. workload_balance
#                             divides by node.memory, which nova reports in MiB.
#
# Memory is the guest's own used figure, `available - unused`, not the host resident set.
# That is what both upstreams mean by this metric: ceilometer's inspect_memory_usage
# computes exactly `available - unused` for memory.usage, and monasca's libvirt check
# computes the same for vm.mem.used_gb -- which is the series metric_map.yaml pointed
# instance_ram_usage at, so it is also what the workload_balance threshold was tuned
# against. balloon.rss is a different quantity: the qemu process's resident set, which
# includes emulator overhead and on a 128 MiB guest measured 133 MiB against a guest-used
# 28.8 MiB. Using it would silently move every memory decision by several multiples.
#
# No nova call is needed to label them: nova sets the libvirt domain UUID to the instance
# UUID, so `virsh list --uuid` is already the value Watcher looks for in the label named
# by instance_uuid_label (default 'resource').
watcher_instance_metrics()
{
    local dir=${1:-/var/lib/node_exporter/textfile}
    local out=$dir/cube_instance_metrics.prom

    # Written wherever node_exporter runs, which is every role. A node with no hypervisor
    # has no virsh and produces an empty file rather than an error -- the series simply do
    # not exist for it, which is what a scrape should see.
    command -v virsh >/dev/null 2>&1 || return 0
    mkdir -p "$dir" || return 1

    {
        echo "# HELP ceilometer_cpu Cumulative CPU time consumed by the instance in nanoseconds."
        echo "# TYPE ceilometer_cpu counter"
        echo "# HELP ceilometer_memory_usage Resident memory of the instance in megabytes."
        echo "# TYPE ceilometer_memory_usage gauge"

        local uuid stats cputime avail unused
        for uuid in $(timeout 20 virsh list --uuid --state-running 2>/dev/null) ; do
            [ -n "$uuid" ] || continue
            # One domstats call per domain for both figures. --balloon reports rss in KiB.
            stats=$(timeout 10 virsh domstats --cpu-total --balloon "$uuid" 2>/dev/null) || continue
            cputime=$(echo "$stats" | sed -n 's/^[[:space:]]*cpu\.time=\([0-9]*\)$/\1/p' | head -1)
            avail=$(echo "$stats" | sed -n 's/^[[:space:]]*balloon\.available=\([0-9]*\)$/\1/p' | head -1)
            unused=$(echo "$stats" | sed -n 's/^[[:space:]]*balloon\.unused=\([0-9]*\)$/\1/p' | head -1)

            [ -n "$cputime" ] && echo "ceilometer_cpu{resource=\"$uuid\"} $cputime"
            # KiB -> MiB. Both figures come from the guest's balloon driver, so a guest
            # without virtio-balloon reports neither and the series is omitted for it --
            # the same thing monasca does, where the check logs "Balloon driver not
            # active/available on guest" and publishes nothing. Omitting is deliberate:
            # substituting balloon.rss would keep the series alive while quietly changing
            # what it measures, which is worse for a threshold than an absent series.
            if [ -n "$avail" ] && [ -n "$unused" ] ; then
                echo "ceilometer_memory_usage{resource=\"$uuid\"} $(( (avail - unused) / 1024 ))"
            fi
        done
    } > "$out.tmp" || { rm -f "$out.tmp" ; return 1 ; }

    # node_exporter reads the whole directory on every scrape, so a half-written file is a
    # parse error that fails the entire textfile collector, not just these series. Rename
    # rather than write in place.
    mv -f "$out.tmp" "$out"
}
