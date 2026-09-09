# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

# One libvirt read per running domain, as an XML block and a stats block with markers
# between them. Two virsh calls per domain rather than one domstats for the whole host,
# because domstats keys its output by domain name and every label below needs the XML
# anyway -- so the second call saves nothing and costs a name-to-uuid mapping.
_instance_metrics_dump()
{
    local name

    for name in $(timeout 20 virsh list --name --state-running 2>/dev/null) ; do
        [ -n "$name" ] || continue
        timeout 10 virsh dumpxml "$name" 2>/dev/null
        echo "@@STATS@@"
        timeout 10 virsh domstats --cpu-total --balloon --block --interface "$name" 2>/dev/null
        echo "@@END@@"
    done
}

# Per-instance metrics, written as a node_exporter textfile.
#
# Nothing else in the stack produces them. node_exporter covers the host half and no
# packaged exporter covers the VM half: the upstream libvirt exporter has had no commit
# since June 2021 and prometheus-community declined to adopt it, which fails the same
# provenance test that rejected kafka_exporter. Ceilometer plus sg-core would cover it, at
# the cost of two more services, another bus consumer and a second agent on every compute
# node -- for twelve series that can be read out of libvirt directly.
#
# Three consumers, and they are why the shape is what it is:
#
#   Watcher    ceilometer_cpu and ceilometer_memory_usage, through its prometheus
#              datasource, for the workload_balance strategy.
#   Grafana    the Instance and Top Instances dashboards, both of which were monasca's.
#   Kapacitor  the two per-project VM alert templates, which are fed the influx line
#              protocol instance_metrics_publish derives from the same read.
#
# The names are Watcher's, not ours, and the two it reads are not negotiable. Its prometheus
# datasource hardcodes instance_cpu_usage -> ceilometer_cpu and instance_ram_usage ->
# ceilometer_memory_usage in METRIC_MAP, and _build_prometheus_query then dispatches on the
# meter name and raises "Cannot process prometheus meter" for anything it does not
# recognise. metric_map_path can rename the meter but that only breaks the dispatch, so
# emitting the ceilometer names is what keeps the backported datasource pristine -- and lets
# the patch be dropped entirely on Epoxy, which ships it. The rest of the family follows the
# same convention, the ceilometer meter name with dots turned to underscores, so that if
# CubeCOS ever does adopt ceilometer every consumer here keeps working unchanged.
#
# Units follow from Watcher's own arithmetic, so its two are fixed:
#   ceilometer_cpu            counter, cumulative NANOSECONDS. Watcher computes
#                             clamp_max((rate(...)/10e+8) * (100/vcpus), 100), so seconds
#                             would read 1e9 times low and always clamp to nothing.
#   ceilometer_memory_usage   gauge, MEBIBYTES, read with avg_over_time. workload_balance
#                             divides by node.memory, which nova reports in MiB.
#
# There are three memory figures here and they are not interchangeable. libvirt reports
# `available` (what the guest can see), `unused` (the guest's MemFree) and `usable` (the
# guest's MemAvailable -- MemFree plus the page cache it could reclaim). balloon.rss, the
# qemu process's resident set, is a fourth and is none of them: it carries emulator
# overhead and on a 128 MiB Cirros guest measured 120 MiB against a guest-used 28 MiB.
#
#   ceilometer_memory_usage            available - unused, which is exactly what
#                                      ceilometer's inspect_memory_usage computes for its
#                                      memory.usage meter. Watcher's meter, Watcher's
#                                      definition.
#   cube_instance_memory_visible_mb    available.
#   cube_instance_memory_usable_mb     usable.
#
# The last two are outside the ceilometer family because ceilometer has no meter for
# either: its `memory` is the flavor's RAM, not what the guest ended up seeing. They exist
# because the human-facing consumers -- the Grafana gauge and the Kapacitor threshold --
# are defined against monasca's vm.mem.free_perc, and that is `usable / available * 100`.
# Measured on the accept-3cc Cirros guest: available 112676 KiB, unused 83116, usable
# 93064, so monasca reported 17.4% used where the ceilometer definition gives 26.2%.
# Publishing one number and calling it both would either move every VM memory alert
# operators have tuned, or misstate an upstream meter. So both are published, and which
# one a consumer reads is a deliberate choice rather than an accident of naming.
#
# Everything else is a counter straight out of libvirt, left cumulative. monasca published
# pre-divided rates (vm.io.read_bytes_sec and friends) because InfluxDB had no rate operator
# worth using; Prometheus has rate(), and a counter survives a missed scrape where a
# collector-computed rate does not.
#
# No nova API call is needed for any of the labels. nova sets the libvirt domain UUID to the
# instance UUID -- so `resource` is already the value Watcher looks for in the label named by
# instance_uuid_label -- and it writes the name, the owning project and the flavor into the
# domain XML as a nova:instance metadata block, which is where the rest come from. That
# matters on a compute node, which holds no OpenStack credentials and should not need any to
# report on the domains it is running.
#
# The influx half, posted to the Kapacitor write proxy on :9092 rather than to InfluxDB on
# :8086. That is the only ingress that replicates -- kapacitor relays what it proxies out to
# its peers, and it is also what feeds the stream tasks, so a point written straight to
# InfluxDB would reach neither the other control nodes nor the alert that is the whole
# reason for writing it. Same endpoint and same shape logstash's persisters use.
#
# A failure here is not a failure of the collection: the textfile is already on disk and
# Prometheus will scrape it regardless, so this returns non-zero and the caller carries on.
_instance_metrics_ship()
{
    local lp=$1

    [ -s "$lp" ] || return 0

    $CURL -sf -X POST --data-binary @"$lp" \
        "http://$(shared_id):9092/write?db=telegraf&rp=def&precision=s" >/dev/null 2>&1
}

# Usage: $PROG instance_metrics_collect [textfile_dir]
instance_metrics_collect()
{
    local dir=${1:-/var/lib/node_exporter/textfile}
    local out=$dir/cube_instance_metrics.prom
    local state=/run/cube_instance_metrics.state
    local now=$(date +%s)
    local lp

    # Runs wherever node_exporter does, which is every role. A node with no hypervisor has
    # no virsh and produces nothing rather than an error -- the series simply do not exist
    # for it, which is what a scrape should see.
    command -v virsh >/dev/null 2>&1 || return 0
    mkdir -p "$dir" || return 1

    # One libvirt read, two outputs: the awk writes the textfile to OUT and the influx line
    # protocol to stdout. Splitting this into two functions would mean walking every domain
    # twice for the same numbers.
    lp=$(MakeTemp)
    _instance_metrics_dump | awk -v OUT="$out.tmp" -v STATE="$state" -v NOW="$now" '
function esc(v) {
    gsub(/\\/, "\\\\", v)
    gsub(/"/, "\\\"", v)
    return v
}
# The XML is entity-encoded and a label value must not be. & is expanded last, or an
# encoded &amp;lt; would come back out as a tag delimiter. \047 is the apostrophe, spelled
# in octal so this whole program can stay a single-quoted shell word.
function unent(v) {
    gsub(/&lt;/, "<", v)
    gsub(/&gt;/, ">", v)
    gsub(/&quot;/, "\"", v)
    gsub(/&apos;/, "\047", v)
    gsub(/&amp;/, "\\&", v)
    return v
}
# Text of <tag ...>text</tag>, attributes or not -- nova:project carries the project id as
# one, so a form that only understands <tag> would miss it.
function tagval(line, tag,   s, rest, g, e) {
    s = index(line, "<" tag)
    if (s == 0) return ""
    rest = substr(line, s + length(tag) + 1)
    g = index(rest, ">")
    if (g == 0) return ""
    rest = substr(rest, g + 1)
    e = index(rest, "</" tag ">")
    if (e == 0) return ""
    return unent(substr(rest, 1, e - 1))
}
function attrval(line, attr,   s, rest, e) {
    s = index(line, attr "=\"")
    if (s == 0) return ""
    rest = substr(line, s + length(attr) + 2)
    e = index(rest, "\"")
    if (e == 0) return ""
    return unent(substr(rest, 1, e - 1))
}
function emit(metric, extra, value) {
    if (value == "") return
    printf "%s{resource=\"%s\",project=\"%s\",project_name=\"%s\",name=\"%s\"%s} %s\n",
           metric, esc(uuid), esc(project), esc(project_name), esc(name), extra, value > OUT
}
# Tag values in influx line protocol escape comma, equals and space, and nothing else --
# a backslash is literal there, so unlike the Prometheus label above it is left alone. The
# four-backslash replacements are awk gsub syntax: two produce one literal backslash in the
# output, so the pair before the delimiter is what emits a single escaping backslash.
function lpesc(v) {
    gsub(/,/, "\\,", v)
    gsub(/=/, "\\=", v)
    gsub(/ /, "\\ ", v)
    return v
}
# Per-second rate of a libvirt counter, from the previous run of this function. Empty
# unless there are two samples and a positive interval -- a VM that booted since the last
# run publishes its first rate one run later, which is what monasca did too. A counter
# below its previous value means the domain was recreated, so the delta is meaningless.
function rate(key, cur) {
    if (cur == "" || dt <= 0 || !(key in prevv) || cur + 0 < prevv[key]) return ""
    return (cur - prevv[key]) / dt
}
function reset() {
    uuid = ""; domname = ""; name = ""; project = ""; project_name = ""; vcpus = ""
    in_meta = 0
    delete st
}
function flush(   i, cnt, dev, extra, avail, unused, usable, tags, dtags, pct, r) {
    if (uuid == "") return
    # A domain libvirt is running but nova did not create. Nothing in CubeCOS makes one,
    # but the label still has to be defined rather than left holding the previous domain.
    if (name == "") name = domname

    emit("ceilometer_cpu", "", st["cpu.time"])
    emit("ceilometer_vcpus", "", vcpus)

    # All three come from the guest balloon driver, so a guest without virtio-balloon
    # reports none of them and every memory series is omitted for it -- the same thing
    # monasca does, where the check logs "Balloon driver not active/available on guest" and
    # publishes nothing. Omitting is deliberate: substituting balloon.rss would keep the
    # series alive while quietly changing what it measures, which is worse for a threshold
    # than an absent series. Each is guarded on its own because an older virtio-balloon
    # reports available and unused without usable.
    #
    # KiB -> MiB, and not rounded to whole MiB: on a 128 MiB guest a truncation moved the
    # percentage the Grafana gauge shows by nearly a point, which is the sort of drift that
    # makes a dashboard and an alert disagree for no reason.
    avail = st["balloon.available"]
    unused = st["balloon.unused"]
    usable = st["balloon.usable"]
    if (avail != "") {
        emit("cube_instance_memory_visible_mb", "", avail / 1024)
        if (unused != "")
            emit("ceilometer_memory_usage", "", (avail - unused) / 1024)
        if (usable != "")
            emit("cube_instance_memory_usable_mb", "", usable / 1024)
    }

    cnt = st["block.count"] + 0
    for (i = 0; i < cnt; i++) {
        dev = st["block." i ".name"]
        if (dev == "") continue
        extra = sprintf(",device=\"%s\"", esc(dev))
        emit("ceilometer_disk_device_read_bytes", extra, st["block." i ".rd.bytes"])
        emit("ceilometer_disk_device_write_bytes", extra, st["block." i ".wr.bytes"])
        emit("ceilometer_disk_device_read_requests", extra, st["block." i ".rd.reqs"])
        emit("ceilometer_disk_device_write_requests", extra, st["block." i ".wr.reqs"])
    }

    cnt = st["net.count"] + 0
    for (i = 0; i < cnt; i++) {
        dev = st["net." i ".name"]
        if (dev == "") continue
        extra = sprintf(",device=\"%s\"", esc(dev))
        emit("ceilometer_network_incoming_bytes", extra, st["net." i ".rx.bytes"])
        emit("ceilometer_network_outgoing_bytes", extra, st["net." i ".tx.bytes"])
        emit("ceilometer_network_incoming_packets", extra, st["net." i ".rx.pkts"])
        emit("ceilometer_network_outgoing_packets", extra, st["net." i ".tx.pkts"])
    }

    # And the same read, as the two influx measurements the per-project Kapacitor VM alert
    # templates stream from. Measurement names, tag names and the field name are exactly
    # the ones monasca published, so re-sourcing those templates is a one-line dbrp change
    # and every threshold an operator has tuned keeps meaning what it meant. Only the
    # database moves.
    tags = sprintf("resource_id=%s,tenant_id=%s,tenant_name=%s,vm_name=%s",
                   lpesc(uuid), lpesc(project), lpesc(project_name), lpesc(name))

    if (st["cpu.time"] != "") {
        r = rate("cpu:" uuid, st["cpu.time"])
        if (r != "" && vcpus + 0 > 0) {
            pct = r / 1e9 * 100 / vcpus
            if (pct > 100) pct = 100
            printf "vm.cpu.utilization_norm_perc,%s value=%.6f %s\n", tags, pct, NOW
        }
        newst["cpu:" uuid] = st["cpu.time"]
    }
    # usable / available, the figure the monasca libvirt check publishes -- see the header.
    if (avail + 0 > 0 && usable != "")
        printf "vm.mem.free_perc,%s value=%.6f %s\n", tags, usable / avail * 100, NOW

    # host_alive_status is what stats_inactive_vm_drop keys its pruning on: a resource_id
    # that has stopped appearing is one whose series can go. Published for every running
    # domain, which is the same statement monasca made with it.
    printf "vm.host_alive_status,%s value=0 %s\n", tags, NOW

    # The four per-second rates the UI reads through hex_sdk stats_topten_vm and
    # stats_vm_chart. Pre-divided, unlike their Prometheus counterparts, because InfluxQL
    # has no rate operator worth using -- which is the reason monasca published them this
    # way and the reason those queries are shaped around it.
    cnt = st["block.count"] + 0
    for (i = 0; i < cnt; i++) {
        dev = st["block." i ".name"]
        if (dev == "") continue
        dtags = tags sprintf(",device=%s", lpesc(dev))
        r = rate("brd:" uuid ":" dev, st["block." i ".rd.bytes"])
        if (r != "") printf "vm.io.read_bytes_sec,%s value=%.6f %s\n", dtags, r, NOW
        r = rate("bwr:" uuid ":" dev, st["block." i ".wr.bytes"])
        if (r != "") printf "vm.io.write_bytes_sec,%s value=%.6f %s\n", dtags, r, NOW
        newst["brd:" uuid ":" dev] = st["block." i ".rd.bytes"]
        newst["bwr:" uuid ":" dev] = st["block." i ".wr.bytes"]
    }

    cnt = st["net.count"] + 0
    for (i = 0; i < cnt; i++) {
        dev = st["net." i ".name"]
        if (dev == "") continue
        dtags = tags sprintf(",device=%s", lpesc(dev))
        r = rate("nrx:" uuid ":" dev, st["net." i ".rx.bytes"])
        if (r != "") printf "vm.net.in_bytes_sec,%s value=%.6f %s\n", dtags, r, NOW
        r = rate("ntx:" uuid ":" dev, st["net." i ".tx.bytes"])
        if (r != "") printf "vm.net.out_bytes_sec,%s value=%.6f %s\n", dtags, r, NOW
        newst["nrx:" uuid ":" dev] = st["net." i ".rx.bytes"]
        newst["ntx:" uuid ":" dev] = st["net." i ".tx.bytes"]
    }
}
BEGIN {
    # The previous sample of every counter that a consumer wants as a per-second rate. In
    # /run rather than /var: a counter delta across a reboot is meaningless, so losing it
    # there is correct, and the first run after boot simply publishes no rate.
    while ((getline line < STATE) > 0) {
        split(line, a, " ")
        if (a[1] == "@") { prev_t = a[2] + 0 ; continue }
        prevv[a[1]] = a[2] + 0
    }
    close(STATE)
    dt = NOW - prev_t

    reset()
    print "# HELP ceilometer_cpu Cumulative CPU time consumed by the instance in nanoseconds." > OUT
    print "# TYPE ceilometer_cpu counter" > OUT
    print "# HELP ceilometer_vcpus Virtual CPUs allocated to the instance." > OUT
    print "# TYPE ceilometer_vcpus gauge" > OUT
    print "# HELP ceilometer_memory_usage Guest memory in use in megabytes, libvirt available minus unused." > OUT
    print "# TYPE ceilometer_memory_usage gauge" > OUT
    print "# HELP cube_instance_memory_visible_mb Memory the guest OS can see in megabytes, libvirt balloon.available." > OUT
    print "# TYPE cube_instance_memory_visible_mb gauge" > OUT
    print "# HELP cube_instance_memory_usable_mb Memory the guest OS could still allocate in megabytes, libvirt balloon.usable." > OUT
    print "# TYPE cube_instance_memory_usable_mb gauge" > OUT
    print "# HELP ceilometer_disk_device_read_bytes Cumulative bytes read from a virtual disk." > OUT
    print "# TYPE ceilometer_disk_device_read_bytes counter" > OUT
    print "# HELP ceilometer_disk_device_write_bytes Cumulative bytes written to a virtual disk." > OUT
    print "# TYPE ceilometer_disk_device_write_bytes counter" > OUT
    print "# HELP ceilometer_disk_device_read_requests Cumulative read requests to a virtual disk." > OUT
    print "# TYPE ceilometer_disk_device_read_requests counter" > OUT
    print "# HELP ceilometer_disk_device_write_requests Cumulative write requests to a virtual disk." > OUT
    print "# TYPE ceilometer_disk_device_write_requests counter" > OUT
    print "# HELP ceilometer_network_incoming_bytes Cumulative bytes received on a virtual interface." > OUT
    print "# TYPE ceilometer_network_incoming_bytes counter" > OUT
    print "# HELP ceilometer_network_outgoing_bytes Cumulative bytes sent on a virtual interface." > OUT
    print "# TYPE ceilometer_network_outgoing_bytes counter" > OUT
    print "# HELP ceilometer_network_incoming_packets Cumulative packets received on a virtual interface." > OUT
    print "# TYPE ceilometer_network_incoming_packets counter" > OUT
    print "# HELP ceilometer_network_outgoing_packets Cumulative packets sent on a virtual interface." > OUT
    print "# TYPE ceilometer_network_outgoing_packets counter" > OUT
}
$0 == "@@STATS@@" { section = "stats" ; next }
$0 == "@@END@@"   { flush() ; reset() ; section = "" ; next }
section == "stats" {
    n = index($0, "=")
    if (n > 1) {
        k = $0 ; sub(/^[ \t]+/, "", k) ; k = substr(k, 1, index(k, "=") - 1)
        st[k] = substr($0, n + 1)
    }
    next
}
# The bare <uuid> is the domain own id; every other uuid in the XML is an attribute
# (nova:project, nova:user, nova:root, nova:port) and cannot match this.
/^[ \t]*<uuid>/             { if (uuid == "") uuid = tagval($0, "uuid") ; next }
/^[ \t]*<name>/             { if (domname == "") domname = tagval($0, "name") ; next }
/<nova:instance /           { in_meta = 1 }
/<\/nova:instance>/         { in_meta = 0 }
in_meta && /<nova:name>/    { name = tagval($0, "nova:name") }
in_meta && /<nova:vcpus>/   { vcpus = tagval($0, "nova:vcpus") }
in_meta && /<nova:project / { project = attrval($0, "uuid") ; project_name = tagval($0, "nova:project") }
END {
    printf "@ %s\n", NOW > STATE
    for (k in newst)
        printf "%s %s\n", k, newst[k] > STATE
    close(STATE)
}
' > "$lp" || { rm -f "$out.tmp" ; RemoveTempFiles ; return 1 ; }

    # node_exporter reads the whole directory on every scrape, so a half-written file is a
    # parse error that fails the entire textfile collector, not just these series. Rename
    # rather than write in place.
    mv -f "$out.tmp" "$out"

    _instance_metrics_ship "$lp"
    RemoveTempFiles
}
