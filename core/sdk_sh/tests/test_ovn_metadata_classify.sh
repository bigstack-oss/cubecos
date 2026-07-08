#!/bin/bash
#
# Unit test for the bulk OVN metadata liveness logic in ../modules/sdk_ovn.sh:
#   _ovn_metadata_classify  -- partitions lagging agents into stuck vs catching-up from a
#                              single nb_cfg + one bulk sb-cfg snapshot (O(1) ovn calls).
#   _ovn_metadata_sbcfg_all -- the Chassis / Chassis_Private join parser (real csv format).
#
# Self-contained: extracts just those two functions, mocks the OVN getters, so it needs no
# cluster/OVN.  Run: bash test_ovn_metadata_classify.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_ovn.sh"
eval "$(awk '/^_ovn_metadata_classify\(\)/{f=1} f{print} f&&/^}/{exit}' "$SRC")"
eval "$(awk '/^_ovn_metadata_sbcfg_all\(\)/{f=1} f{print} f&&/^}/{exit}' "$SRC")"
[ "$(type -t _ovn_metadata_classify)" = function ] || { echo "FAIL: classify not extracted"; exit 1; }

export _OVN_SBCFG_DIR=$(mktemp -d)
pass=0 fail=0
ck(){ [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

# ---- classify: mock nb_cfg + the bulk snapshot ----
MOCK_NB=""; MOCK_SNAP=""
_ovn_nb_cfg(){ echo "$MOCK_NB"; }
_ovn_metadata_sbcfg_all(){ printf '%s' "$MOCK_SNAP"; }   # "<host> <sbcfg>" lines
bucket(){ case " $OVN_META_STUCK " in *" $1 "*) echo stuck; return;; esac
          case " $OVN_META_CATCHING " in *" $1 "*) echo catching; return;; esac; echo clear; }
run1(){  # <host> <nb> <cur|''> <last|''>
    MOCK_NB="$2"; { [ -n "$3" ] && MOCK_SNAP="$1 $3"; } || MOCK_SNAP=""
    { [ -n "$4" ] && echo "$4" > "$_OVN_SBCFG_DIR/health_neutron_sbcfg_$1"; } || rm -f "$_OVN_SBCFG_DIR/health_neutron_sbcfg_$1"
    _ovn_metadata_classify "$1"
}
run1 h1 100 100 '' ; ck "$(bucket h1)" clear    "caught_up (cur==nb)"
run1 h1 100 105 '' ; ck "$(bucket h1)" clear    "ahead (cur>nb)"
run1 h2 100 90  80 ; ck "$(bucket h2)" catching "advancing (90>80)"
run1 h3 100 90  '' ; ck "$(bucket h3)" catching "first-seen while lagging"
run1 h4 100 90  90 ; ck "$(bucket h4)" stuck    "frozen (90==90)"
run1 h5 100 90  95 ; ck "$(bucket h5)" stuck    "backwards (90<95)"
run1 h6 ""  90  '' ; ck "$(bucket h6)" stuck    "empty nb_cfg -> fail-safe"
run1 h7 100 ''  '' ; ck "$(bucket h7)" stuck    "host absent from snapshot -> fail-safe"
run1 h8 100 70  '' ; ck "$(cat "$_OVN_SBCFG_DIR/health_neutron_sbcfg_h8")" 70 "state file updated to cur"

# bulk: one classify call partitions many hosts at once
MOCK_NB=100; MOCK_SNAP=$'a 100\nb 90\nc 90'
echo 88 > "$_OVN_SBCFG_DIR/health_neutron_sbcfg_b"   # b advancing 88->90
echo 90 > "$_OVN_SBCFG_DIR/health_neutron_sbcfg_c"   # c frozen 90->90
_ovn_metadata_classify "a b c"
ck "$(bucket a)" clear    "bulk: a caught_up"
ck "$(bucket b)" catching "bulk: b advancing"
ck "$(bucket c)" stuck    "bulk: c frozen"

# ---- parser: _ovn_metadata_sbcfg_all via an ovn-sbctl PATH shim (real csv format) ----
# restore the real parser (it was mocked above for the classify tests)
eval "$(awk '/^_ovn_metadata_sbcfg_all\(\)/{f=1} f{print} f&&/^}/{exit}' "$SRC")"
shim=$(mktemp -d)
cat > "$shim/chassis.csv" <<'EOF'
"""cd8bd37f-72d3-44a5-9d7a-b8198641c842""",sky142
"""ada4ccfe-d238-42b2-ad85-96a2de41bc1a""",sky143
"""fcf50a31-d9c0-4779-be93-a6beaa1e2807""",sky141
EOF
cat > "$shim/priv.csv" <<'EOF'
"""ada4ccfe-d238-42b2-ad85-96a2de41bc1a""","{""neutron:ovn-metadata-id""=""x"", ""neutron:ovn-metadata-sb-cfg""=""42140"", ""neutron:ovn-vpnagent-sb-cfg""=""42147""}"
"""fcf50a31-d9c0-4779-be93-a6beaa1e2807""","{""neutron:ovn-metadata-sb-cfg""=""42147"", ""neutron:ovn-vpnagent-sb-cfg""=""42147""}"
EOF
cat > "$shim/ovn-sbctl" <<EOF
#!/bin/bash
case "\$*" in
  *"list Chassis_Private"*) cat "$shim/priv.csv" ;;
  *"list Chassis"*)         cat "$shim/chassis.csv" ;;
esac
EOF
chmod +x "$shim/ovn-sbctl"
# sky142 present in Chassis but absent from Chassis_Private -> correctly omitted.
# must pick metadata-sb-cfg (42140/42147), never vpnagent-sb-cfg.
out=$(PATH="$shim:$PATH" _ovn_metadata_sbcfg_all | sort | tr '\n' ';')
ck "$out" "sky141 42147;sky143 42140;" "parser join: metadata sb-cfg only, missing-priv host omitted"

rm -rf "$_OVN_SBCFG_DIR" "$shim"
echo "----"; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: _ovn_metadata_classify + _ovn_metadata_sbcfg_all"; exit 0; } || exit 1
