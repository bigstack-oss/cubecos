#!/bin/bash
#
# Unit test for the Skyline-WebSSO helpers in ../modules/sdk_advisor.sh:
# advisor_sso_origins_set/list/clear and advisor_sso_apply.
#
# A line in the origins file authorises keystone to post an unscoped token to
# that URL -- keystone substitutes the matched origin into
# sso_callback_template.html as the form action -- so most of what follows is
# about what the validator refuses. The rest is that apply derives the two
# files correctly and touches the services only when something changed:
# restarting keystone on every commit would drop federated logins in progress.
#
# Self-contained: extracts only the functions under test, so it needs none of
# sdk_advisor.sh's runtime prerequisites (PROG / SDK_DIR / errcodes).
# Run:  bash test_sdk_advisor_sso.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_advisor.sh"

for f in _advisor_write_file _advisor_sso_origin_valid \
         advisor_sso_origins_set advisor_sso_origins_list \
         advisor_sso_origins_clear _advisor_sso_hosts \
         _advisor_sso_file_changed advisor_sso_apply \
         advisor_sso_origins_set_cluster advisor_sso_origins_clear_cluster \
         advisor_sso_reported_list advisor_sso_reported_set \
         advisor_sso_effective_list advisor_sso_report_read \
         advisor_sso_report_apply advisor_sso_origins_show \
         _advisor_sso_base_valid _advisor_target_name_valid \
         advisor_sso_reported_bases advisor_sso_reported_base ; do
    fn="$(awk -v want="^$f\\\\(\\\\)" '$0 ~ want {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || { echo "FAIL: $f not found in $SRC"; exit 1; }
    eval "$fn"
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0 fail=0
ok()    { pass=$((pass+1)); }
bad()   { fail=$((fail+1)); echo "FAIL: $1"; }
check() { if [ "$2" = "$3" ] ; then ok ; else bad "$1: got '$2', want '$3'" ; fi ; }

ADVISOR_SSO_ORIGINS_FILE="$WORK/etc/cube-advisor-agent/sso-origins"
ADVISOR_SSO_REPORTED_FILE="$WORK/etc/cube-advisor-agent/sso-origins-reported"
ADVISOR_SSO_AGENT_REPORT="$WORK/etc/cube/advisor-agent/console-origins"
ADVISOR_AGENT_CERT="$WORK/etc/cube/advisor-agent/agent.crt"
ADVISOR_SSO_TARGET=cube-cos-skyline
ADVISOR_SSO_CALLBACK_PATH=/api/openstack/skyline/api/v1/websso
ADVISOR_SSO_KEYSTONE_FILE="$WORK/etc/keystone/cube-advisor-origins"
ADVISOR_SSO_MELLON_FILE="$WORK/etc/httpd/conf.d/zz-cube-advisor-mellon.conf"

# apply's only side effects on a real node. Recorded rather than run: what
# matters is whether they happen at all, and how often.
# Keycloak's half talks to a live server over the network, which a unit test
# has none of. Recorded rather than run: what belongs here is that apply calls
# it, not what it does when it gets an answer.
keycloak_applies=0
advisor_sso_keycloak_apply() { keycloak_applies=$((keycloak_applies+1)) ; return 0 ; }

restarts=0 reloads=0
systemctl() {
    case "$*" in
        *"is-active"*) return 0 ;;
        "restart openstack-keystone") restarts=$((restarts+1)) ;;
        "reload httpd")              reloads=$((reloads+1)) ;;
    esac
    return 0
}

ADDR='https://10.32.1.61:9999/api/openstack/skyline/api/v1/websso'
WILD='https://cube-cos-skyline--*.adv.example.com/api/openstack/skyline/api/v1/websso'

# --- what the validator accepts -------------------------------------------
for url in \
    "$ADDR" \
    "$WILD" \
    'https://console.example.com/api/openstack/skyline/api/v1/websso' \
    'https://10.0.0.1:443/x' ; do
    if _advisor_sso_origin_valid "$url" ; then ok ; else bad "should accept: $url" ; fi
done

# --- and what it refuses ---------------------------------------------------
# Each of these is a way to make keystone post a token somewhere the operator
# did not name, or a shape the keystone-side matcher would compare differently.
for url in \
    'http://10.32.1.61:9999/api/openstack/skyline/api/v1/websso' \
    'https://evil@10.32.1.61:9999/x' \
    'https://10.32.1.61:9999/x?next=https://evil.test' \
    'https://10.32.1.61:9999/x#f' \
    'https://10.32.1.61:9999' \
    'https://10.32.1.61:0/x' \
    'https://10.32.1.61:99999/x' \
    'https://10.32.1.61:http/x' \
    'https:///x' \
    'https://10.32.1.61 evil.test/x' \
    'ftp://10.32.1.61/x' \
    '10.32.1.61:9999/x' \
    '' ; do
    if _advisor_sso_origin_valid "$url" ; then bad "should refuse: $url" ; else ok ; fi
done

# The cluster setter hands these to a remote shell, so the path charset has to
# stay narrow enough that no URL can carry a second command with it.
for url in \
    "https://10.32.1.61:9999/x';reboot;'" \
    'https://10.32.1.61:9999/x$(reboot)' \
    'https://10.32.1.61:9999/x`reboot`' \
    'https://10.32.1.61:9999/x;reboot' \
    'https://10.32.1.61:9999/x|reboot' \
    'https://10.32.1.61:9999/x&reboot' \
    'https://10.32.1.61:9999/x reboot' ; do
    if _advisor_sso_origin_valid "$url" ; then bad "should refuse shell metacharacters: $url" ; else ok ; fi
done

# --- set / list / clear ----------------------------------------------------
advisor_sso_origins_set "$ADDR" "$WILD"
check "list returns both, in order" "$(advisor_sso_origins_list)" "$ADDR
$WILD"

# One bad entry fails the whole call: a partially applied trust list is worse
# than none, because nobody can tell which half landed.
before="$(advisor_sso_origins_list)"
if advisor_sso_origins_set "$ADDR" 'http://evil.test/x' 2>/dev/null ; then
    bad "set accepted a bad url"
else
    ok
fi
check "a rejected set changes nothing" "$(advisor_sso_origins_list)" "$before"

# The file migrates across a firmware upgrade, so a line this release would
# not have written can still turn up in it.
printf '%s\n%s\n%s\n' "$ADDR" 'http://evil.test/x' '# a comment' > "$ADVISOR_SSO_ORIGINS_FILE"
check "list drops lines this release rejects" "$(advisor_sso_origins_list)" "$ADDR"

# --- apply ----------------------------------------------------------------
advisor_sso_origins_set "$ADDR" "$WILD"
restarts=0 reloads=0
advisor_sso_apply
check "keystone gets the origins verbatim" "$(cat "$ADVISOR_SSO_KEYSTONE_FILE")" "$ADDR
$WILD"
check "mellon gets the hosts, with [self] kept" "$(cat "$ADVISOR_SSO_MELLON_FILE")" "<Location /v3>
    MellonRedirectDomains [self] 10.32.1.61 cube-cos-skyline--*.adv.example.com
</Location>"
check "keystone restarted once" "$restarts" "1"
check "httpd reloaded once" "$reloads" "1"

# A commit that changes nothing must not bounce keystone: every federated
# login in flight would lose its assertion.
restarts=0 reloads=0
advisor_sso_apply
check "an unchanged apply restarts nothing" "$restarts" "0"
check "an unchanged apply reloads nothing" "$reloads" "0"

# Adding an origin is a change.
advisor_sso_origins_set "$ADDR"
restarts=0 reloads=0
advisor_sso_apply
check "narrowing the list restarts keystone" "$restarts" "1"
check "narrowing the list reloads httpd" "$reloads" "1"
check "keystone file follows" "$(cat "$ADVISOR_SSO_KEYSTONE_FILE")" "$ADDR"

# Clearing the record withdraws the trust rather than leaving it behind.
advisor_sso_origins_clear
restarts=0 reloads=0
advisor_sso_apply
if [ -e "$ADVISOR_SSO_KEYSTONE_FILE" ] ; then bad "keystone file outlived the record" ; else ok ; fi
if [ -e "$ADVISOR_SSO_MELLON_FILE" ] ; then bad "mellon file outlived the record" ; else ok ; fi
check "withdrawing restarts keystone" "$restarts" "1"
check "withdrawing reloads httpd" "$reloads" "1"

# A node that never enrolled: nothing recorded, nothing written, nothing
# restarted. This is the common case on every cluster that has no Advisor.
restarts=0 reloads=0
advisor_sso_apply
check "no record writes no files" "$(ls "$WORK/etc/keystone" 2>/dev/null)" ""
check "no record restarts nothing" "$restarts" "0"

# --- cluster fan-out -------------------------------------------------------
# keystone answers from every control node behind the VIP, so a list recorded
# on one of them makes the login succeed or fail by which backend haproxy
# picked. What matters here is that every node is visited and that the URL
# survives the remote shell as one word -- the wildcard entry is a glob.
CUBE_NODE_LIST_HOSTNAMES=(ctrl1 ctrl2 ctrl3)
HEX_SDK=/usr/sbin/hex_sdk
REMOTE_LOG="$WORK/remote.log"
remote_run() { printf '%s\t%s\n' "$1" "$2" >> "$REMOTE_LOG" ; }

: > "$REMOTE_LOG"
advisor_sso_origins_set_cluster "$ADDR" "$WILD"
check "every node is visited" "$(cut -f1 "$REMOTE_LOG" | tr '\n' ' ')" "ctrl1 ctrl2 ctrl3 "
check "the wildcard url is quoted for the remote shell" \
    "$(head -1 "$REMOTE_LOG" | cut -f2)" \
    "/usr/sbin/hex_sdk advisor_sso_origins_set '$ADDR' '$WILD' && /usr/sbin/hex_sdk advisor_sso_apply"

# A bad URL is refused before any node is touched: half a cluster trusting an
# origin is worse than none of it, because nothing says which half.
: > "$REMOTE_LOG"
if advisor_sso_origins_set_cluster "$ADDR" 'http://evil.test/x' 2>/dev/null ; then
    bad "cluster set accepted a bad url"
else
    ok
fi
check "a rejected cluster set touches no node" "$(cat "$REMOTE_LOG")" ""

: > "$REMOTE_LOG"
advisor_sso_origins_clear_cluster
check "clear reaches every node" "$(cut -f1 "$REMOTE_LOG" | tr '\n' ' ')" "ctrl1 ctrl2 ctrl3 "


# --- the Advisor's own report -----------------------------------------------
# What the agent was told on connect, turned into a callback URL and trusted
# alongside whatever an operator declared. Two halves kept apart so the
# Advisor's can withdraw itself without taking an operator's entry with it.
mkdir -p "$(dirname "$ADVISOR_SSO_AGENT_REPORT")"
# Enrolled, for the fan-out guard below. A node with no identity does not
# speak for the Advisor and must not act on a report it could not have.
: > "$ADVISOR_AGENT_CERT"
advisor_sso_origins_clear
advisor_sso_reported_set

report() { printf '%s\n' "$@" > "$ADVISOR_SSO_AGENT_REPORT" ; }

report "cube-cos https://10.32.1.61" "cube-cos-skyline https://10.32.1.61:9999"
check "the whole report travels, not one composed url" \
    "$(advisor_sso_report_read)" "cube-cos https://10.32.1.61
cube-cos-skyline https://10.32.1.61:9999"

# Domain mode reports a base with a wildcard where the session id goes; it has
# to survive composition, because it is the only form that can name a
# per-session origin at all.
report "cube-cos-skyline https://cube-cos-skyline--*.adv.example.com"
check "a wildcard base survives the trip" \
    "$(advisor_sso_report_read)" \
    "cube-cos-skyline https://cube-cos-skyline--*.adv.example.com"

# A trailing slash on the base must not produce a doubled slash: keystone
# compares the path exactly, so "//api/..." is a different origin.
advisor_sso_reported_set cube-cos-skyline https://10.32.1.61:9999
check "a trailing slash does not double" "$(advisor_sso_reported_list)" "$ADDR"

# A report this release would not have written can still turn up — an older or
# newer Advisor, or a file that crossed an upgrade.
report "cube-cos-skyline http://10.32.1.61:9999" "cube-cos-skyline https://a b/x" "malformed"
check "a report that does not validate is dropped" "$(advisor_sso_report_read)" ""

# --- the union --------------------------------------------------------------
advisor_sso_reported_set cube-cos-skyline https://10.32.1.61:9999
advisor_sso_origins_set "$WILD"
check "both halves are trusted" "$(advisor_sso_effective_list)" "$ADDR
$WILD"

advisor_sso_origins_set "$ADDR"
check "a duplicate across the halves appears once" "$(advisor_sso_effective_list)" "$ADDR"

# The Advisor withdrawing its origin must not touch the operator's.
advisor_sso_origins_set "$WILD"
advisor_sso_reported_set
check "withdrawing the report leaves the operator record" \
    "$(advisor_sso_effective_list)" "$WILD"

# And an operator clearing theirs must not touch the Advisor's.
advisor_sso_reported_set cube-cos-skyline https://10.32.1.61:9999
advisor_sso_origins_clear
check "clearing the operator record leaves the report" \
    "$(advisor_sso_effective_list)" "$ADDR"

# apply works off the union, so mellon gets both hosts.
advisor_sso_origins_set "$WILD"
restarts=0 reloads=0
advisor_sso_apply
check "keystone is given both halves" "$(cat "$ADVISOR_SSO_KEYSTONE_FILE")" "$ADDR
$WILD"
check "mellon is given both hosts" "$(cat "$ADVISOR_SSO_MELLON_FILE")" "<Location /v3>
    MellonRedirectDomains [self] 10.32.1.61 cube-cos-skyline--*.adv.example.com
</Location>"

# An operator deciding whether to clear an entry has to be able to tell which
# half it came from: one withdraws itself, the other does not.
advisor_sso_reported_set cube-cos-skyline https://10.32.1.61:9999
advisor_sso_origins_set "$WILD"
check "show labels each entry with its source" "$(advisor_sso_origins_show)" \
    "$ADDR (reported by the Advisor)
$WILD (declared here)"

# --- carrying the report to the cluster -------------------------------------
# The agent runs only on enrolled nodes; keystone answers on every control node
# behind the VIP. Reading the report in place would trust the origin on one
# node and refuse it on the next.
report "cube-cos-skyline https://10.32.1.61:9999"
: > "$REMOTE_LOG"
advisor_sso_report_apply
check "the report reaches every node" "$(cut -f1 "$REMOTE_LOG" | tr '\n' ' ')" "ctrl1 ctrl2 ctrl3 "
check "each node records and applies it" "$(head -1 "$REMOTE_LOG" | cut -f2)" \
    "/usr/sbin/hex_sdk advisor_sso_reported_set 'cube-cos-skyline' 'https://10.32.1.61:9999' && /usr/sbin/hex_sdk advisor_sso_apply"

# A report naming no console origin is a statement — the console was turned off
# — and must withdraw the trust everywhere, not leave it behind.
: > "$ADVISOR_SSO_AGENT_REPORT"
: > "$REMOTE_LOG"
advisor_sso_report_apply
check "an empty report withdraws on every node" "$(head -1 "$REMOTE_LOG" | cut -f2)" \
    "/usr/sbin/hex_sdk advisor_sso_reported_set && /usr/sbin/hex_sdk advisor_sso_apply"


# --- what each consumer takes from the report -------------------------------
# The three of them need different parts, which is why the raw report travels
# rather than one composed URL. Keycloak's is the one that broke: it compares
# the browser's Origin header, which carries a port, and the mellon helper
# strips ports because mellon matches hostnames.
advisor_sso_origins_clear
advisor_sso_reported_set cube-cos https://10.32.1.61 \
                         cube-cos-skyline https://10.32.1.61:9999 \
                         cube-cos-idp https://10.32.1.61:10443

check "keystone gets Skyline's callback url" "$(advisor_sso_reported_list)" "$ADDR"
check "mellon gets hostnames, no ports" "$(_advisor_sso_hosts)" "10.32.1.61"
check "keycloak gets the idp origin, with its port" \
    "$(advisor_sso_reported_base cube-cos-idp)" "https://10.32.1.61:10443"
check "a target that was not reported has no base" \
    "$(advisor_sso_reported_base cube-cos-ceph)" ""

# A base is an origin, not a URL: anything with a path would be appended to and
# produce nonsense.
for b in "https://10.32.1.61:10443" "https://h--*.d.example.com" "https://h" ; do
    if _advisor_sso_base_valid "$b" ; then ok ; else bad "should accept base: $b" ; fi
done
for b in "http://10.32.1.61" "https://10.32.1.61/path" "https://u@h" "https://h:0" \
         "https://h:99999" "https://" "" ; do
    if _advisor_sso_base_valid "$b" ; then bad "should refuse base: $b" ; else ok ; fi
done


# --- the guard on speaking for the Advisor ----------------------------------
# A node with no identity has no agent and so no report. Absence there means
# "nothing was told to me", not "the Advisor reports no console origin", and
# acting on it would withdraw the whole cluster's trust from a node that was
# never in a position to know.
report "cube-cos-skyline https://10.32.1.61:9999"
mv "$ADVISOR_AGENT_CERT" "$ADVISOR_AGENT_CERT.away"
: > "$REMOTE_LOG"
advisor_sso_report_apply
check "an unenrolled node touches no node" "$(cat "$REMOTE_LOG")" ""
mv "$ADVISOR_AGENT_CERT.away" "$ADVISOR_AGENT_CERT"

# And with an identity it does act, so the guard is the identity and not a
# permanent off switch.
: > "$REMOTE_LOG"
advisor_sso_report_apply
check "an enrolled node fans out" "$(cut -f1 "$REMOTE_LOG" | tr '\n' ' ')" "ctrl1 ctrl2 ctrl3 "

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
