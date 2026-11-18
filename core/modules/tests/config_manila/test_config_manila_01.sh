#
# TEST - config_manila selects the volume type of the default backend (#2363)
#   1. default storage ext1, tuning unset          -> ext1
#   2. default storage CubeStorage, tuning ext1    -> ext1
#   3. default storage CubeStorage, tuning unset   -> CubeStorage
#   4. default storage ext1, tuning CubeStorage    -> CubeStorage
#   5. default storage ext1, tuning empty          -> ext1
#   6. no default storage, tuning unset            -> CubeStorage
#
# Each case starts from an empty /etc/settings.txt, so the role change alone makes the
# module commit. Role compute skips database, keystone and share type setup.
#

CONF=/etc/manila/manila.conf

fail() { echo "FAIL: $1"; exit 1; }

BASE="cubesys.role=compute
net.hostname=node1"

# $1 = case name, $2.. = extra settings lines
run_case() {
    local name=$1 ; shift
    : > /etc/settings.txt
    rm -f $CONF
    { printf '%s\n' "$BASE" ; [ $# -gt 0 ] && printf '%s\n' "$@" ; } > /tmp/settings.txt
    # non-zero exit is not a failure here: only the module under test is linked
    ./hex_config -vvve commit /tmp/settings.txt >"/tmp/commit_manila_$name.log" 2>&1 || true
}

# $1 = case name, $2 = expected volume type
check_type() {
    local actual
    actual=$(awk '
        /^[[:space:]]*\[/ { generic = ($0 ~ /^[[:space:]]*\[generic\][[:space:]]*$/) }
        generic && /^[[:space:]]*cinder_volume_type[[:space:]]*=/ {
            sub(/^[^=]*=[[:space:]]*/, "")
            sub(/[[:space:]]*$/, "")
            print
        }
    ' "$CONF" 2>/dev/null)
    [ "$actual" = "$2" ] || fail "$1: expected $2, actual cinder_volume_type='$actual'"
    echo "  ok  $1 -> $actual"
}

# ---- 1. unset tuning follows external default storage ----
run_case external_default "cinder.storage.volumeType.default=ext1"
check_type external_default ext1

# ---- 2. external tuning overrides built-in default storage ----
run_case external_override "cinder.storage.volumeType.default=CubeStorage" "manila.volume.type=ext1"
check_type external_override ext1

# ---- 3. unset tuning follows built-in default storage ----
run_case builtin_default "cinder.storage.volumeType.default=CubeStorage"
check_type builtin_default CubeStorage

# ---- 4. built-in tuning overrides external default storage (#2363) ----
run_case builtin_override "cinder.storage.volumeType.default=ext1" "manila.volume.type=CubeStorage"
check_type builtin_override CubeStorage

# ---- 5. an explicitly empty tuning follows default storage ----
# HexTuningParseLine accepts name= as an empty value.
run_case empty "cinder.storage.volumeType.default=ext1" "manila.volume.type="
check_type empty ext1

# ---- 6. no default storage either: the built-in type ----
run_case builtin_fallback "cinder.storage.volumeType.default="
check_type builtin_fallback CubeStorage

echo "config_manila: all cases passed"
