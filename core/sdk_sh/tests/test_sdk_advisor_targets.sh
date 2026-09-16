#!/bin/bash
#
# Unit test for the node-side web-target allowlist helpers in
# ../modules/sdk_advisor.sh: advisor_targets_init/list/set/unset, plus the
# discovered-targets file init seeds the rest of the names from.
#
# The allowlist is the node's veto over what the Advisor agent may dial, so
# what matters here is not just that reads and writes work, but that the
# file is never repaired out from under an operator and never left
# half-written. Both are exercised below. init seeds more than it used to --
# every node now seeds its own at commit time -- and seeding still means
# "write one where there is none", never "reconcile the one that is there".
#
# Self-contained: extracts only the functions under test, so it needs none of
# sdk_advisor.sh's runtime prerequisites (PROG / SDK_DIR / errcodes).
# Run:  bash test_sdk_advisor_targets.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_advisor.sh"

for f in _advisor_target_name_valid _advisor_target_address_valid \
         _advisor_write_file _advisor_targets_write \
         advisor_discovered_set advisor_discovered_list \
         advisor_targets_init advisor_targets_list advisor_targets_set advisor_targets_unset ; do
    fn="$(awk -v want="^$f\\\\(\\\\)" '$0 ~ want {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || { echo "FAIL: $f not found in $SRC"; exit 1; }
    eval "$fn"
done

# The dashboard address comes from this node's settings, which a unit test has
# none of. Stubbed to a fixed value: what these cases check is what gets seeded,
# not how the address is discovered. Its identity provider is derived from it,
# and is stubbed here for the same reason.
advisor_dashboard_address() { echo "10.0.0.1:443"; }
advisor_idp_address() { echo "10.0.0.1:10443"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0 fail=0
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); echo "FAIL: $1"; }
check() { if [ "$2" = "$3" ] ; then ok ; else bad "$1: got '$2', want '$3'" ; fi ; }

ADVISOR_TARGETS_FILE="$WORK/etc/web-targets.json"
# Nothing discovered unless a case below records something.
ADVISOR_DISCOVERED_FILE="$WORK/etc/discovered-targets"

# --- nothing discovered: init seeds the targets every node can name for
# --- itself, and only those --------------------------------------------------
# The dashboard and its identity provider, on two ports of one address: the
# dashboard sends the browser at the second, so seeding one without the other
# seeds a login that cannot complete.
advisor_targets_init
check "init creates the file" "$(cat "$ADVISOR_TARGETS_FILE" 2>/dev/null)" \
      '{"cube-cos":"10.0.0.1:443","cube-cos-idp":"10.0.0.1:10443"}'
check "init leaves the file root-owned and world-readable" \
      "$(stat -c %a "$ADVISOR_TARGETS_FILE" 2>/dev/null)" "644"

# --- init must never repair or overwrite a file that is already there -------
# An operator who removed a target removed it on purpose.
printf '{"cube-cos":"10.0.0.1:443","cmp-portal":"10.32.1.101:443"}' > "$ADVISOR_TARGETS_FILE"
advisor_targets_init
check "a second init leaves an edited file untouched" "$(cat "$ADVISOR_TARGETS_FILE")" \
      '{"cube-cos":"10.0.0.1:443","cmp-portal":"10.32.1.101:443"}'

# --- the set a node was given, and what init makes of it --------------------
ADVISOR_DISCOVERED_FILE="$WORK/etc/discovered-targets"
advisor_discovered_set app-fw-idp 10.32.1.101:443 cube-cmp 10.32.1.101:443
check "discovered_set records one name and address per line" \
      "$(cat "$ADVISOR_DISCOVERED_FILE")" \
      "$(printf 'app-fw-idp 10.32.1.101:443\ncube-cmp 10.32.1.101:443')"
check "discovered_list reads it back" "$(advisor_discovered_list | sort)" \
      "$(printf 'app-fw-idp 10.32.1.101:443\ncube-cmp 10.32.1.101:443')"

if advisor_discovered_set cube-cmp "10.32.1.101 ; rm -rf /:443" 2>/dev/null ; then
    bad "discovered_set accepted an address that is not a literal host"
else
    ok
fi
if advisor_discovered_set Bad_Name 10.32.1.101:443 2>/dev/null ; then
    bad "discovered_set accepted an invalid target name"
else
    ok
fi
if advisor_discovered_set cube-cmp 2>/dev/null ; then
    bad "discovered_set accepted a name with no address"
else
    ok
fi

# A node that was never told anything: silent, no output, not an error.
ADVISOR_DISCOVERED_FILE="$WORK/etc/no-such-discovered"
out="$(advisor_discovered_list 2>"$WORK/err")" || bad "discovered_list failed with no file"
check "discovered_list prints nothing with no file" "$out" ""
check "discovered_list says nothing on stderr with no file" "$(cat "$WORK/err")" ""

# A hand-mangled line is dropped rather than turned into an allowlist entry.
ADVISOR_DISCOVERED_FILE="$WORK/etc/mangled"
printf 'cube-cmp 10.32.1.101:443\nnot a valid line at all\nbad-port 10.0.0.1:abc\n' \
    > "$ADVISOR_DISCOVERED_FILE"
check "discovered_list keeps only the well-formed lines" "$(advisor_discovered_list)" \
      "cube-cmp 10.32.1.101:443"

# With a set recorded, init seeds exactly those names as well. Both CMP names
# at the same address: the portal and its IdP must share one origin.
ADVISOR_DISCOVERED_FILE="$WORK/etc/discovered-targets"
ADVISOR_TARGETS_FILE="$WORK/etc/seeded-with-discovered.json"
advisor_targets_init
check "init seeds cube-cos" "$(advisor_targets_list | sed -n 's/^cube-cos //p')" "10.0.0.1:443"
check "init seeds cube-cos-idp" "$(advisor_targets_list | sed -n 's/^cube-cos-idp //p')" "10.0.0.1:10443"
check "init seeds cube-cmp at the discovered address" \
      "$(advisor_targets_list | sed -n 's/^cube-cmp //p')" "10.32.1.101:443"
check "init seeds app-fw-idp at the discovered address" \
      "$(advisor_targets_list | sed -n 's/^app-fw-idp //p')" "10.32.1.101:443"
check "init seeds exactly those four" "$(advisor_targets_list | grep -c .)" "4"

# The framework installed and CMP not: init seeds what was discovered and not
# one name more. The ingress exists in both cases, so only the set can tell
# these two apart.
ADVISOR_DISCOVERED_FILE="$WORK/etc/discovered-framework-only"
advisor_discovered_set app-fw-idp 10.32.1.101:443
ADVISOR_TARGETS_FILE="$WORK/etc/seeded-framework-only.json"
advisor_targets_init
check "framework only: init seeds app-fw-idp" \
      "$(advisor_targets_list | sed -n 's/^app-fw-idp //p')" "10.32.1.101:443"
check "framework only: init does not seed cube-cmp" \
      "$(advisor_targets_list | grep -c '^cube-cmp ')" "0"
check "framework only: init seeds exactly three" "$(advisor_targets_list | grep -c .)" "3"

# ... and still never touches a file that exists, even one an operator has
# taken a CMP target back out of. "A node with no allowlist gets one" is not
# "every node is reconciled to a canonical set".
ADVISOR_DISCOVERED_FILE="$WORK/etc/discovered-targets"
ADVISOR_TARGETS_FILE="$WORK/etc/operator-edited.json"
printf '{"cube-cos":"10.0.0.1:443","app-fw-idp":"10.32.1.101:443"}\n' > "$ADVISOR_TARGETS_FILE"
before="$(cat "$ADVISOR_TARGETS_FILE")"
advisor_targets_init
check "init leaves an operator-edited allowlist byte-for-byte alone" \
      "$(cat "$ADVISOR_TARGETS_FILE")" "$before"
check "init did not put back the target the operator unset" \
      "$(advisor_targets_list | grep -c '^cube-cmp ')" "0"

ADVISOR_DISCOVERED_FILE="$WORK/etc/no-such-discovered"
ADVISOR_TARGETS_FILE="$WORK/etc/web-targets.json"

# --- set adds -----------------------------------------------------------
rm -f "$ADVISOR_TARGETS_FILE"
advisor_targets_init >/dev/null
advisor_targets_set cmp-portal 10.32.1.101:443
check "set adds a new name" "$(advisor_targets_list | grep -c .)" "3"
check "set records the value" "$(advisor_targets_list | sed -n 's/^cmp-portal //p')" "10.32.1.101:443"

# --- set on an existing name replaces, not duplicates -----------------------
advisor_targets_set cmp-portal 10.32.1.101:8443
check "set on an existing name still leaves one entry" "$(advisor_targets_list | grep -c .)" "3"
check "set on an existing name replaces the value" "$(advisor_targets_list | sed -n 's/^cmp-portal //p')" "10.32.1.101:8443"

# --- unset removes -----------------------------------------------------------
advisor_targets_unset cmp-portal
check "unset removes the name" "$(advisor_targets_list | sed -n 's/^cmp-portal //p')" ""
check "unset leaves the rest of the file" "$(advisor_targets_list | grep -c .)" "2"

# --- unset of an absent name is not an error --------------------------------
if advisor_targets_unset never-was >/dev/null 2>&1 ; then
    ok
else
    bad "unset of a name that was never there was refused"
fi

# --- an invalid name is refused, loudly, and nothing is written -------------
before="$(cat "$ADVISOR_TARGETS_FILE")"
if advisor_targets_set Bad_Name 10.0.0.1:80 2>/dev/null ; then
    bad "an invalid target name was accepted"
else
    ok
fi
check "an invalid name did not change the file" "$(cat "$ADVISOR_TARGETS_FILE")" "$before"

if advisor_targets_set "" 10.0.0.1:80 >/dev/null 2>&1 ; then
    bad "an empty target name was accepted"
else
    ok
fi

if advisor_targets_unset Bad_Name >/dev/null 2>&1 ; then
    bad "unset accepted an invalid name"
else
    ok
fi

# --- an invalid port is refused, loudly, and nothing is written -------------
before="$(cat "$ADVISOR_TARGETS_FILE")"
if advisor_targets_set new-target 10.0.0.1:99999 2>/dev/null ; then
    bad "a port above 65535 was accepted"
else
    ok
fi
check "an out-of-range port did not change the file" "$(cat "$ADVISOR_TARGETS_FILE")" "$before"

if advisor_targets_set new-target 10.0.0.1:0 >/dev/null 2>&1 ; then
    bad "port 0 was accepted"
else
    ok
fi

if advisor_targets_set new-target 10.0.0.1:abc >/dev/null 2>&1 ; then
    bad "a non-numeric port was accepted"
else
    ok
fi

if advisor_targets_set new-target no-colon-here >/dev/null 2>&1 ; then
    bad "a target with no port was accepted"
else
    ok
fi
check "the file is still untouched after every rejected write" "$(cat "$ADVISOR_TARGETS_FILE")" "$before"

# --- a failed write leaves the previous file intact -------------------------
# Simulate a write that cannot land its temp file (disk full, read-only fs,
# whatever) by making mktemp fail, and confirm the old content survives.
before="$(cat "$ADVISOR_TARGETS_FILE")"
mktemp() { return 1; }
if advisor_targets_set another-one 10.0.0.2:80 2>/dev/null ; then
    bad "set reported success although its write could not be made"
else
    ok
fi
unset -f mktemp
check "a failed write leaves the previous file intact" "$(cat "$ADVISOR_TARGETS_FILE")" "$before"

# --- fixtures an operator would actually produce -----------------------------
# The suite above only ever wrote fixtures in the exact compact form this
# module emits. A regex reader would pass every one of those and still lose
# every hand-edited or re-formatted file in the field, so these read the file
# with jq instead and exercise the shapes an editor, jq itself, or
# python -m json.tool would actually leave behind.

# pretty-printed, a space after every colon, real indentation
ADVISOR_TARGETS_FILE="$WORK/pretty.json"
cat > "$ADVISOR_TARGETS_FILE" <<'JSON'
{
  "cube-cos": "10.0.0.1:443",
  "cmp-portal": "10.32.1.101:443"
}
JSON
check "list reads a pretty-printed file" "$(advisor_targets_list | sort)" \
      "$(printf 'cmp-portal 10.32.1.101:443\ncube-cos 10.0.0.1:443')"
advisor_targets_set new-one 1.2.3.4:80
check "set on a pretty-printed file keeps the existing entries" \
      "$(advisor_targets_list | grep -c .)" "3"

# padded single-line object: { "a" : "1.2.3.4:80" }
ADVISOR_TARGETS_FILE="$WORK/padded.json"
printf '{ "a" : "1.2.3.4:80" }' > "$ADVISOR_TARGETS_FILE"
check "list reads a padded single-line file" "$(advisor_targets_list)" "a 1.2.3.4:80"
advisor_targets_set b 5.6.7.8:9
check "set on a padded file keeps the existing entry" "$(advisor_targets_list | grep -c .)" "2"

# not JSON at all -- set must refuse and change nothing
ADVISOR_TARGETS_FILE="$WORK/notjson.json"
printf 'this is not json\n' > "$ADVISOR_TARGETS_FILE"
before="$(cat "$ADVISOR_TARGETS_FILE")"
if advisor_targets_set a 1.2.3.4:1 2>/dev/null ; then
    bad "set accepted a file that is not JSON"
else
    ok
fi
check "a non-JSON file is unchanged after a rejected set" "$(cat "$ADVISOR_TARGETS_FILE")" "$before"
if advisor_targets_unset a 2>/dev/null ; then
    bad "unset accepted a file that is not JSON"
else
    ok
fi
check "a non-JSON file is unchanged after a rejected unset" "$(cat "$ADVISOR_TARGETS_FILE")" "$before"

# zero-byte file -- jq runs its filter zero times over this and calls it
# success, so this has to be caught by hand
ADVISOR_TARGETS_FILE="$WORK/empty.json"
: > "$ADVISOR_TARGETS_FILE"
if advisor_targets_set a 1.2.3.4:1 2>/dev/null ; then
    bad "set accepted a zero-byte file"
else
    ok
fi
check "a zero-byte file is still zero bytes after a rejected set" \
      "$(wc -c < "$ADVISOR_TARGETS_FILE")" "0"

# CRLF line endings
ADVISOR_TARGETS_FILE="$WORK/crlf.json"
printf '{\r\n  "a" : "1.2.3.4:80"\r\n}\r\n' > "$ADVISOR_TARGETS_FILE"
check "list reads a CRLF file" "$(advisor_targets_list)" "a 1.2.3.4:80"
advisor_targets_set b 5.6.7.8:9
check "set on a CRLF file keeps the existing entry" "$(advisor_targets_list | grep -c .)" "2"

# port 08 -- digit-only and range checks both pass a leading zero
ADVISOR_TARGETS_FILE="$WORK/leadingzero.json"
advisor_targets_init >/dev/null
before="$(cat "$ADVISOR_TARGETS_FILE")"
if advisor_targets_set c 1.2.3.4:08 2>/dev/null ; then
    bad "a port with a leading zero was accepted"
else
    ok
fi
check "a leading-zero port did not change the file" "$(cat "$ADVISOR_TARGETS_FILE")" "$before"

# unset of a name that is a prefix of another must only remove the exact key
ADVISOR_TARGETS_FILE="$WORK/prefix.json"
advisor_targets_init >/dev/null
advisor_targets_set cmp 10.0.0.1:1
advisor_targets_set cmp-portal 10.32.1.101:443
advisor_targets_unset cmp
check "unset of a name that prefixes another leaves the longer name" \
      "$(advisor_targets_list | sed -n 's/^cmp-portal //p')" "10.32.1.101:443"
check "unset of a name that prefixes another removes only the exact key" \
      "$(advisor_targets_list | grep -c '^cmp ')" "0"

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
