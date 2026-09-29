#!/bin/bash
#
# Unit test for the 1 s utilization window collectors in ../modules/sdk_gpu.sh
# (#1547): gpu_util_window_parse, gpu_util_window_tags, gpu_vm_util_window and
# gpu_host_util_window.
#
# The snapshot collectors (gpu_vm_stats / gpu_host_stats) record one instant
# every 5 minutes, and a 2-minute busy loop in a vGPU VM on cn13 fell between
# two of them. The window collectors sample every second instead; what is pinned
# here is that the peak and mean come out right, land in the snapshot's own
# series, and that sampling is actually bounded (an unbounded `vgpu -u` never
# returns, which would wedge the telegraf input).
#
# Fixtures come from cn13 (2026-09-24, cubecos scratch
# cn13-vram-workload-check-20260924): the vgpu -q records are cn13.txt's, the
# busy values are the busy VM's rows of vramtest2/poll.u.stuck-1s.txt. The
# original `vgpu -u` header was inferred. A separate cn13 capture from
# 2026-10-09 (driver 580.105.08) pins the real header, idle-card '-' rows and
# MIG-backed vGPU N/A rows without replacing the busy and reordered fixtures.
#
#   Run: bash test_gpu_util_window.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GPU_SRC="$DIR/../modules/sdk_gpu.sh"

extract() { awk -v fn="^$1\\\\(\\\\)" '$0 ~ fn {f=1} f{print} f&&/^}/{exit}' "$2"; }

for fn in gpu_stats_parse gpu_util_window_parse gpu_util_window_tags \
          gpu_vm_util_window gpu_host_util_window ; do
    eval "$(extract $fn "$GPU_SRC")"
    [ "$(type -t $fn)" = function ] || { echo "FAIL: $fn not extracted"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
HOSTNAME=cn13
TS=1790000000000000000

gpu_is_installed() { return 0; }
date() { echo 1790000000; }

# timeout stub: records how it was called, then runs the command and exits 124
# like a real timeout ending `vgpu -u` / `-l 1` (neither exits on its own). It
# must record rather than swallow: "sampling is bounded" is a claim about this
# call, and a no-op stub would let a version that never calls it pass.
TIMEOUT_LOG="$TMP/timeout.log"
TIMEOUT_RC=124
timeout() { echo "$*" >> "$TIMEOUT_LOG"; shift; "$@"; return $TIMEOUT_RC; }

# nvidia-smi stub, answering by subcommand from files and logging each call so
# the order of sampling and snapshot can be checked.
NVIDIA_SMI="$TMP/nvidia-smi"
cat > "$NVIDIA_SMI" <<'STUB'
#!/bin/bash
echo "$*" >> "$STUB_DIR/calls"
case "$*" in
    "vgpu -u")       cat "$STUB_DIR/vgpu_u" ;;
    "vgpu -q")       cat "$STUB_DIR/vgpu_q" ;;
    --query-gpu=*)   cat "$STUB_DIR/query_gpu" ;;
    "-q")            cat "$STUB_DIR/q" ;;
esac
STUB
chmod +x "$NVIDIA_SMI"
export STUB_DIR="$TMP"

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); printf 'FAIL: %s\n  got:  %s\n  want: %s\n' "$3" "$1" "$2"; }; }

# --- fixtures ------------------------------------------------------------------
# Two DC-6Q vGPUs on 8C:00.0 and a MIG-backed DC-1-12Q on 42:00.0 (utilization
# N/A in vgpu -q; its vgpu -u columns are assumed to print '-').
cat > "$TMP/vgpu_q" <<'EOF'
GPU 00000000:42:00.0
    Active vGPUs                          : 1
    vGPU ID                               : 3251637444
        VM UUID                           : 6939a743-b4d3-4b8f-b917-a8f7009744ee
        VM Name                           : instance-0000002b
        vGPU Name                         : NVIDIA RTX Pro 6000 Blackwell DC-1-12Q
        FB Memory Usage
            Total                         : 12288 MiB
            Used                          : 784 MiB
            Free                          : 11504 MiB
        Utilization
            GPU                           : N/A
            Memory                        : N/A

GPU 00000000:8C:00.0
    Active vGPUs                          : 2
    vGPU ID                               : 3251642357
        VM UUID                           : 43f26719-90d9-4b25-80eb-040b44132eb8
        VM Name                           : instance-0000002f
        vGPU Name                         : NVIDIA RTX Pro 6000 Blackwell DC-6Q
        FB Memory Usage
            Total                         : 6144 MiB
            Used                          : 256 MiB
            Free                          : 5888 MiB
        Utilization
            GPU                           : 0 %
            Memory                        : 0 %
    vGPU ID                               : 3251642411
        VM UUID                           : e011a1e1-0775-4cd5-9543-a635fb705e81
        VM Name                           : instance-00000030
        vGPU Name                         : NVIDIA RTX Pro 6000 Blackwell DC-6Q
        FB Memory Usage
            Total                         : 6144 MiB
            Used                          : 256 MiB
            Free                          : 5888 MiB
        Utilization
            GPU                           : 0 %
            Memory                        : 0 %
EOF

# Nine seconds of `vgpu -u`. 3251642411 carries the busy VM's measured values
# (95..99 sm) with one unreadable row in the middle; 3251651856 is a vGPU that
# was sampled but is gone by the snapshot (VM shut down during the window).
VGPU_U_HEADER='# gpu        vgpu     sm    mem    enc    dec    jpg    ofa
# Idx          Id      %      %      %      %      %      %'
busy_sm=(0 0 95 98 - 97 98 99 0)
busy_mem=(0 0 92 94 N/A 93 94 95 0)
{
    echo "$VGPU_U_HEADER"
    for i in 0 1 2 3 4 5 6 7 8; do
        printf '    0  3251637444      -      -      -      -      -      -\n'
        printf '    1  3251642357      0      0      0      0      0      0\n'
        printf '    1  3251642411  %5s  %5s      0      0      0      0\n' "${busy_sm[$i]}" "${busy_mem[$i]}"
        [ $i -lt 3 ] && printf '    1  3251651856      0      0      0      0      0      0\n'
    done
} > "$TMP/vgpu_u"

cat > "$TMP/q" <<'EOF'
GPU 00000000:42:00.0
    Product Name                          : NVIDIA RTX PRO 6000 Blackwell Server Edition
    FB Memory Usage
        Total                             : 97887 MiB
        Used                              : 23249 MiB
        Free                              : 72350 MiB
    Utilization
        GPU                               : N/A
        Memory                            : N/A

GPU 00000000:8C:00.0
    Product Name                          : NVIDIA RTX PRO 6000 Blackwell Server Edition
    FB Memory Usage
        Total                             : 97887 MiB
        Used                              : 11840 MiB
        Free                              : 86047 MiB
    Utilization
        GPU                               : 0 %
        Memory                            : 0 %
EOF
# dev util measured 98-99 during the cn13 busy loop (vramtest/poll8c.csv). The
# MIG card reads [N/A] throughout.
cat > "$TMP/query_gpu" <<'EOF'
00000000:42:00.0, [N/A], [N/A]
00000000:8C:00.0, 0, 0
00000000:42:00.0, [N/A], [N/A]
00000000:8C:00.0, 98, 40
00000000:42:00.0, [N/A], [N/A]
00000000:8C:00.0, 99, 41
00000000:42:00.0, [N/A], [N/A]
00000000:8C:00.0, 1, 1
EOF

TAG_444='gpu.vm,gid=3251637444,name=NVIDIA-RTX-Pro-6000-Blackwell-DC-1-12Q,vm_uuid=6939a743-b4d3-4b8f-b917-a8f7009744ee'
TAG_357='gpu.vm,gid=3251642357,name=NVIDIA-RTX-Pro-6000-Blackwell-DC-6Q,vm_uuid=43f26719-90d9-4b25-80eb-040b44132eb8'
TAG_411='gpu.vm,gid=3251642411,name=NVIDIA-RTX-Pro-6000-Blackwell-DC-6Q,vm_uuid=e011a1e1-0775-4cd5-9543-a635fb705e81'
TAG_8C='gpu.host,host=cn13,name=NVIDIA-RTX-PRO-6000-Blackwell-Server-Edition,pciid=00000000:8C:00.0'
TAG_42='gpu.host,host=cn13,name=NVIDIA-RTX-PRO-6000-Blackwell-Server-Edition,pciid=00000000:42:00.0'
WANT_VM="$TAG_357 util_gpu_max=0,util_gpu_mean=0.0,util_mem_max=0,util_mem_mean=0.0,util_samples=9i $TS
$TAG_411 util_gpu_max=99,util_gpu_mean=60.9,util_mem_max=95,util_mem_mean=58.5,util_samples=8i $TS"
WANT_HOST="$TAG_8C util_gpu_max=99,util_gpu_mean=49.5,util_mem_max=41,util_mem_mean=20.5,util_samples=4i $TS"

# The tag files gpu_util_window_tags would cut from these snapshots, written out
# by hand so part A does not depend on gpu_stats_parse.
printf '3251637444\t%s\n3251642357\t%s\n3251642411\t%s\n' "$TAG_444" "$TAG_357" "$TAG_411" > "$TMP/tags_vm"
printf '00000000:42:00.0\t%s\n00000000:8C:00.0\t%s\n' "$TAG_42" "$TAG_8C" > "$TMP/tags_host"

# =============================================================================
# A. gpu_util_window_parse / gpu_util_window_tags -- any POSIX awk
# =============================================================================

# --- A1. vm: peak, mean, sample count per vGPU -----------------------------------
out=$(gpu_util_window_parse vm "$TMP/tags_vm" "$TS" < "$TMP/vgpu_u" 2>"$TMP/err" | sort)
ck "$out" "$WANT_VM" "parse vm: max/mean/samples per vGPU"

# --- A2. unreadable samples drop only themselves ---------------------------------
# 3251642411 has 9 rows, one of them '-'/'N/A': 8 samples; 3251642357 keeps 9.
ck "$(echo "$out" | grep -c "gid=3251642411.*util_samples=8i")" "1" "parse vm: '-' row drops one sample"
ck "$(echo "$out" | grep -c 'gid=3251637444')" "0" "parse vm: MIG-backed vGPU (all '-') -> no line"
ck "$(grep -c 3251637444 "$TMP/err")" "0" "parse vm: MIG-backed vGPU is not an error"

# --- A3. a vGPU missing from the snapshot is dropped and named -------------------
ck "$(echo "$out" | grep -c 3251651856)" "0" "parse vm: vGPU gone by the snapshot -> dropped"
ck "$(grep -c '^gpu_vm_util_window: 3251651856: not in the snapshot' "$TMP/err")" "1" \
   "parse vm: dropped vGPU named on stderr"
ck "$(grep -vc 3251651856 "$TMP/err")" "0" "parse vm: nothing else on stderr"

# --- A4. columns come from the header, not from position -------------------------
{
    echo '# vgpu         gpu    mem     sm'
    awk '!/^#/ {print $2, $1, $4, $3}' "$TMP/vgpu_u"
} > "$TMP/vgpu_u.reordered"
out=$(gpu_util_window_parse vm "$TMP/tags_vm" "$TS" < "$TMP/vgpu_u.reordered" 2>/dev/null | sort)
ck "$out" "$WANT_VM" "parse vm: columns located by header name"

# --- A5. no header / no rows -----------------------------------------------------
grep -v '^#' "$TMP/vgpu_u" > "$TMP/vgpu_u.noheader"
out=$(gpu_util_window_parse vm "$TMP/tags_vm" "$TS" < "$TMP/vgpu_u.noheader" 2>"$TMP/err")
ck "$out" "" "parse vm: rows without header -> no output"
ck "$(grep -c 'read without a column header, dropped' "$TMP/err")" "1" "parse vm: rows without header -> reported once"

out=$(echo "$VGPU_U_HEADER" | gpu_util_window_parse vm "$TMP/tags_vm" "$TS" 2>"$TMP/err")
ck "$out$(cat "$TMP/err")" "" "parse vm: header but no vGPU rows -> silent"
out=$(printf 'No devices were found\n' | gpu_util_window_parse vm "$TMP/tags_vm" "$TS" 2>"$TMP/err")
ck "$out$(cat "$TMP/err")" "" "parse vm: an nvidia-smi message is not a sample -> silent"

# --- A6. host: CSV joined on pciid -----------------------------------------------
out=$(gpu_util_window_parse host "$TMP/tags_host" "$TS" < "$TMP/query_gpu" 2>"$TMP/err")
ck "$out" "$WANT_HOST" "parse host: peak/mean on pciid; MIG card ([N/A]) -> no line"
ck "$(cat "$TMP/err")" "" "parse host: nothing on stderr"

# --- A7. tag file -----------------------------------------------------------------
out=$(printf '%s mem_used=256 \n%s mem_used=11840\n' "$TAG_411" "$TAG_8C" | gpu_util_window_tags gid)
ck "$out" "$(printf '3251642411\t%s' "$TAG_411")" "tags: gid -> measurement,tags; lines without the tag skipped"
out=$(printf '%s mem_used=11840\n' "$TAG_8C" | gpu_util_window_tags pciid)
ck "$out" "$(printf '00000000:8C:00.0\t%s' "$TAG_8C")" "tags: pciid (last tag) -> measurement,tags"

# --- A8. actual cn13 header, idle card and MIG N/A rows ---------------------------
printf '3251711099\t%s\n' "$TAG_357" > "$TMP/tags_real"
out=$(gpu_util_window_parse vm "$TMP/tags_real" "$TS" < "$DIR/fixtures/cn13-vgpu-util-20261009.txt" 2>"$TMP/err")
ck "$out" "$TAG_357 util_gpu_max=0,util_gpu_mean=0.0,util_mem_max=0,util_mem_mean=0.0,util_samples=8i $TS" \
   "parse vm: real cn13 header preserves all 8 numeric samples"
ck "$(cat "$TMP/err")" "" "parse vm: real idle-card and MIG N/A rows are silent"

# =============================================================================
# B. the collectors end to end -- needs gpu_stats_parse, which passes a
#    multi-line -v to awk: gawk (the product's awk) accepts it, the BSD awk of
#    macOS does not.
# =============================================================================
if ! awk -v probe="$(printf 'a\nb')" 'BEGIN {}' 2>/dev/null; then
    echo "SKIP: part B needs an awk that accepts newlines in -v (gawk, as on the product); $(awk --version 2>&1 | head -1)"
else

# --- B1. vm window ------------------------------------------------------------------
: > "$TIMEOUT_LOG"; : > "$TMP/calls"
out=$(gpu_vm_util_window 2>"$TMP/err" | sort); rc=$?
ck "$out" "$WANT_VM" "vm window: max/mean/samples per vGPU"
ck "$rc" "0" "vm window: exit 0"
ck "$(cat "$TMP/err")" "gpu_vm_util_window: 3251651856: not in the snapshot taken after sampling, dropped" \
   "vm window: only the vanished vGPU on stderr (snapshot warnings not repeated)"

# --- B2. the window point lands in the snapshot's own series ------------------------
snap_tags=$("$NVIDIA_SMI" vgpu -q | gpu_stats_parse vm "" 2>/dev/null | awk '{print $1}' | sort)
win_tags=$(echo "$out" | awk '{print $1}' | sort)
ck "$(comm -13 <(echo "$snap_tags") <(echo "$win_tags"))" "" \
   "vm window: every tag set is one gpu_stats_parse produced, verbatim"
ck "$(echo "$snap_tags" | grep -c .)" "3" "vm window: the snapshot itself has all three vGPUs"

# --- B3. sampling is bounded, and happens before the snapshot -----------------------
ck "$(cat "$TIMEOUT_LOG")" "285 $NVIDIA_SMI vgpu -u" "vm window: vgpu -u runs under timeout 285"
ck "$(tr '\n' '|' < "$TMP/calls")" "vgpu -u|vgpu -q|vgpu -q|" \
   "vm window: sampling first, tag snapshot after (then B2's own call)"
: > "$TIMEOUT_LOG"
GPU_UTIL_WINDOW_SEC=5 gpu_vm_util_window >/dev/null 2>&1
ck "$(cat "$TIMEOUT_LOG")" "5 $NVIDIA_SMI vgpu -u" "vm window: GPU_UTIL_WINDOW_SEC overrides the window"

# nvidia-smi dying mid-window keeps what it read, and says so.
TIMEOUT_RC=1
out=$(gpu_vm_util_window 2>"$TMP/err" | sort)
ck "$out" "$WANT_VM" "vm window: early exit keeps the samples read"
ck "$(grep -c 'exited 1 before the window ended' "$TMP/err")" "1" "vm window: early exit reported"
TIMEOUT_RC=124

# --- B4. host window ---------------------------------------------------------------
: > "$TIMEOUT_LOG"; : > "$TMP/calls"
out=$(gpu_host_util_window 2>"$TMP/err")
ck "$out" "$WANT_HOST" "host window: peak/mean joined on pciid; MIG card -> no line"
ck "$(cat "$TMP/err")" "" "host window: nothing on stderr"
ck "$(cat "$TIMEOUT_LOG")" "285 $NVIDIA_SMI --query-gpu=pci.bus_id,utilization.gpu,utilization.memory --format=csv,noheader,nounits -l 1" \
   "host window: query runs under timeout 285"
ck "$(tr '\n' '|' < "$TMP/calls")" "--query-gpu=pci.bus_id,utilization.gpu,utilization.memory --format=csv,noheader,nounits -l 1|-q|" \
   "host window: sampling first, tag snapshot after"

fi

# --- C. not a GPU node ----------------------------------------------------------------
gpu_is_installed() { return 1; }
: > "$TIMEOUT_LOG"
ck "$(gpu_vm_util_window 2>&1)$(gpu_host_util_window 2>&1)" "" "no GPU -> silent"
ck "$(cat "$TIMEOUT_LOG")" "" "no GPU -> nothing sampled"

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
