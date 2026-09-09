#!/bin/bash
#
# Unit test for the storage tier registry side of ../modules/sdk_ceph.sh (#840
# WP-5) -- the registry is where a device tier's Cinder backend comes from, so
# a tier that exists on Ceph and not in the registry is a volume type nobody
# serves:
#   ceph_device_tier_create      -- step 6 registers the tier; a failure there
#                                   is reported and left repairable, never
#                                   unwound, and the idempotent branch
#                                   registers too so re-running completes a
#                                   tier that got as far as step 5
#   ceph_device_tier_list        -- shows the registry against Ceph in both
#                                   directions, and never reads "the registry
#                                   could not be read" as "nothing registered"
#   the four queries cli_ceph.cpp validates against -- each returns non-zero
#                                   rather than an empty answer when it cannot
#                                   read, because the CLI refuses to decide on
#                                   an answer nobody got
#   _ceph_device_tier_health_ok  -- refuses on the checks that mean redundancy
#                                   or availability is compromised right now,
#                                   and only warns on the rest, so that one
#                                   slow op cannot block a tier command for a
#                                   day
#
# That last property is what the whole CLI layer rests on: it is the only
# gatekeeper for device tier input (an indexed tuning array has no hex_config
# validate slot to put a check in), and a name checked against a list that
# failed to load is not checked at all.
#
# Self-contained: extracts those functions and their helpers, stubs ceph /
# openstack / hex_sdk / Quiet against a small cluster model, so it needs no
# cluster.
#   Run: bash test_ceph_device_tier_registry.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_ceph.sh"
for f in ceph_device_tier_create ceph_device_tier_list \
         ceph_device_tier_names ceph_device_tier_names_taken \
         ceph_device_tier_osd_table ceph_device_tier_class_users \
         _ceph_device_tier_name_ok _ceph_device_tier_osd_ids \
         _ceph_device_tier_registry _ceph_device_tier_is_registered \
         _ceph_device_tier_registry_add _ceph_device_tier_unwind_create \
         _ceph_device_tier_class_of_osd _ceph_device_tier_class_hosts \
         _ceph_device_tier_health_ok \
         _ceph_device_tier_has_class _ceph_device_tier_has_rule \
         _ceph_device_tier_has_pool _ceph_device_tier_has_vtype ; do
    eval "$(awk -v n="^$f\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ "$(type -t "$f")" = function ] || { echo "FAIL: $f not extracted"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SETTINGS_TXT="$TMP/settings.txt"
BUILTIN_BACKPOOL=cinder-volumes

# The real Quiet returns the command's status, EXCEPT with -n, which forces 0.
# Reproducing that exactly is the point: `Quiet -n cmd || handler` is dead
# code, and a suite whose Quiet returned the status would not notice a
# regression to it.
Quiet() {
    if [ "${1:-}" = -n ] ; then shift; "$@" >/dev/null 2>&1; return 0; fi
    "$@" >/dev/null 2>&1
}
sleep() { : ; }

# The pool size a tier's own rule can reach is not the property under test
# here, so it is answered rather than derived.
_ceph_device_tier_target_pool_size() { echo 2 ; }

# Two sdk_ceph.sh functions of its own that create leans on. They are stubbed
# rather than extracted because what they do to a real cluster (create a pool
# with an explicit size, then adjust it) is outside what a model can say
# anything true about; what matters here is only that the pool appears.
ceph_create_pool() {
    echo "ceph_create_pool $*" >> "$TMP/calls"
    grep -qx "$1" "$TMP/pools" || echo "$1" >> "$TMP/pools"
    grep -q "^$1:" "$TMP/poolattr" || echo "$1:${3:-1}:1:replicated_rule" >> "$TMP/poolattr"
}
ceph_adjust_pool_size() { echo "ceph_adjust_pool_size $*" >> "$TMP/calls" ; }

# ---- cluster model -------------------------------------------------------
# classes    : "<osd id>:<class>" per line, the authority for class queries
# rules      : rule names, one per line
# pools      : pool names, one per line
# poolattr   : "<pool>:<size>:<min_size>:<crush rule>"
# vtypes     : volume type names, one per line
# ruledump   : `osd crush rule dump -f json`
# pooldetail : `osd pool ls detail -f json`
# settings   : the registry, as translate_ext_storage.cpp writes it
# DEAD_PAT   : a regex; any ceph command matching it fails and changes
#              nothing. Naming the command that breaks, rather than a call
#              index, keeps a case readable when the module reads one more
#              time than it used to.
# OS_DEAD    : 1 makes every openstack call fail
# REGISTRY_ADD_RC : what the policy edit in sdk_cinder.sh returns
reset_cluster() {
    printf '0:hdd\n1:hdd\n2:gold\n3:ssd\n4:\n6:gold\n10:gold\n' > "$TMP/classes"
    printf 'replicated_rule\nrule-ssd\ngold\n' > "$TMP/rules"
    printf 'cinder-volumes\nk8s-volumes\ngold\n' > "$TMP/pools"
    printf 'cinder-volumes:3:2:replicated_rule\nk8s-volumes:3:2:rule-ssd\ngold:2:1:gold\n' > "$TMP/poolattr"
    printf 'CubeStorage\ngold\n' > "$TMP/vtypes"
    cat > "$TMP/ruledump.json" <<'JSON'
[{"rule_id":0,"rule_name":"replicated_rule","steps":[{"op":"take","item_name":"default"},{"op":"emit"}]},
 {"rule_id":1,"rule_name":"rule-ssd","steps":[{"op":"take","item_name":"default~ssd"},{"op":"emit"}]},
 {"rule_id":2,"rule_name":"gold","steps":[{"op":"take","item_name":"default~gold"},{"op":"emit"}]}]
JSON
    cat > "$TMP/pooldetail.json" <<'JSON'
[{"pool_name":"cinder-volumes","crush_rule":0},
 {"pool_name":"k8s-volumes","crush_rule":1},
 {"pool_name":"gold","crush_rule":2}]
JSON
    printf 'cinder.storage.tier.0.name = gold\n' > "$SETTINGS_TXT"
    : > "$TMP/calls"
    DEAD_PAT='^$'
    OS_DEAD=0
    REGISTRY_ADD_RC=0
    HEALTH_STATUS=HEALTH_OK
    HEALTH_CHECKS=
    RECOVERING=null
}

# `ceph -s -f json` as this cluster model sees it. The checks are an object
# keyed by check name, which is the shape _ceph_device_tier_health_ok reads.
status_json() {
    local checks="{}" n=
    for n in $HEALTH_CHECKS ; do
        checks=$(echo "$checks" | jq -c --arg n "$n" \
            '. + {($n): {severity: "HEALTH_WARN", summary: {message: "stub"}}}')
    done
    jq -n -c --arg s "$HEALTH_STATUS" --argjson c "$checks" --arg r "$RECOVERING" \
        '{health: {status: $s, checks: $c},
          pgmap: {recovering_objects_per_sec: (if $r == "null" then null else ($r | tonumber) end)}}'
}

# osd tree, built from the class model so that a class change is visible to the
# next read. osd.4 carries no class, which is what an OSD looks like after a
# tier it belonged to was deleted.
osd_tree_json() {
    jq -n --arg model "$(cat "$TMP/classes")" '
        ($model | split("\n") | map(select(length > 0) | split(":"))) as $osds
        | { nodes:
            ( [ { id: -1, name: "default", type: "root", children: [-3,-5,-7] },
                { id: -3, name: "cube451", type: "host", children: [0,2,3] },
                { id: -5, name: "cube452", type: "host", children: [1,6] },
                { id: -7, name: "cube453", type: "host", children: [4,10] } ]
              + [ $osds[] | { id: (.[0] | tonumber), name: ("osd." + .[0]), type: "osd",
                              device_class: (.[1] // ""), status: "up" } ] ) }'
}

fake_ceph() {
    local cmd="$*"
    echo "$cmd" | grep -qE "$DEAD_PAT" && return 1
    local pool= attr= id=
    case "$cmd" in
        '-s')                          : ;;
        '-s -f json')                  status_json ;;
        'osd crush class ls')          cut -d: -f2 "$TMP/classes" | awk 'length && !seen[$0]++' | jq -R . | jq -s -c . ;;
        'osd crush rule ls')           cat "$TMP/rules" ;;
        'osd pool ls')                 cat "$TMP/pools" ;;
        'osd pool ls detail -f json')  cat "$TMP/pooldetail.json" ;;
        'osd crush rule dump'*)        cat "$TMP/ruledump.json" ;;
        'osd tree -f json')            osd_tree_json ;;
        'osd ls')                      cut -d: -f1 "$TMP/classes" ;;
        'osd crush class ls-osd '*)    awk -F: -v c="${cmd##* }" '$2 == c { print $1 }' "$TMP/classes" ;;
        'osd crush rm-device-class osd.'*)
            id=${cmd##*osd.}
            sed -i.bak "s/^$id:.*/$id:/" "$TMP/classes" ;;
        'osd crush set-device-class '*)
            id=$(echo "$cmd" | awk '{print $NF}') ; id=${id#osd.}
            sed -i.bak "s/^$id:.*/$id:$(echo "$cmd" | awk '{print $4}')/" "$TMP/classes" ;;
        'osd crush rule create-replicated '*)
            echo "$cmd" | awk '{print $5}' >> "$TMP/rules" ;;
        'osd pool set '*' crush_rule '*)
            pool=$(echo "$cmd" | awk '{print $4}')
            sed -i.bak "s/^$pool:\([^:]*\):\([^:]*\):.*/$pool:\1:\2:$(echo "$cmd" | awk '{print $6}')/" "$TMP/poolattr" ;;
        'osd pool delete '*)
            pool=$(echo "$cmd" | awk '{print $4}')
            grep -vx "$pool" "$TMP/pools" > "$TMP/x" ; mv "$TMP/x" "$TMP/pools"
            grep -v "^$pool:" "$TMP/poolattr" > "$TMP/x" ; mv "$TMP/x" "$TMP/poolattr" ;;
        'osd crush rule rm '*)
            grep -vx "${cmd##* }" "$TMP/rules" > "$TMP/x" ; mv "$TMP/x" "$TMP/rules" ;;
        'osd pool get '*)
            pool=$(echo "$cmd" | awk '{print $4}')
            attr=$(grep "^$pool:" "$TMP/poolattr")
            [ -n "$attr" ] || return 1
            case "$cmd" in
                *' size -f json')       echo "{\"size\":$(echo "$attr" | cut -d: -f2)}" ;;
                *' min_size -f json')   echo "{\"min_size\":$(echo "$attr" | cut -d: -f3)}" ;;
                *' crush_rule -f json') echo "{\"crush_rule\":\"$(echo "$attr" | cut -d: -f4)\"}" ;;
            esac ;;
        *) echo "unstubbed ceph: $cmd" >> "$TMP/calls" ;;
    esac
    return 0
}
CEPH=fake_ceph

fake_openstack() {
    [ "$OS_DEAD" = 0 ] || return 1
    case "$*" in
        *'volume type list'*)   cat "$TMP/vtypes" ;;
        *'volume type delete'*) grep -vx "$4" "$TMP/vtypes" > "$TMP/x" ; mv "$TMP/x" "$TMP/vtypes" ;;
    esac
    return 0
}
OPENSTACK=fake_openstack

# hex_sdk: the two things sdk_ceph.sh has to shell back out for. hex_sdk sources
# only the module matching the command's own prefix, so under a ceph_* command
# neither os_volume_type_create nor the sdk_cinder.sh policy edit is defined at
# all -- which is why they are reached this way and why this stub dispatches on
# the subcommand instead of answering everything alike.
fake_sdk() {
    case "$1" in
        os_volume_type_create)
            echo "$2" >> "$TMP/vtypes" ; return 0 ;;
        cinder_apply_storage_tier_creation)
            echo "registry_add $2" >> "$TMP/calls"
            [ "$REGISTRY_ADD_RC" = 0 ] || return "$REGISTRY_ADD_RC"
            echo "cinder.storage.tier.$(wc -l < "$SETTINGS_TXT" | tr -d ' ').name = $2" >> "$SETTINGS_TXT"
            return 0 ;;
    esac
    return 1
}
HEX_SDK=fake_sdk

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }
ckhas() { case "$1" in *"$2"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL: $3 -> output lacks '$2'";; esac; }
cklacks() { case "$1" in *"$2"*) fail=$((fail+1)); echo "FAIL: $3 -> output should not contain '$2'";; *) pass=$((pass+1));; esac; }

# ==== step 6: create registers the tier ==================================

# ---- 1a. the happy path registers exactly once ----
reset_cluster
OUT=$(ceph_device_tier_create silver 0 1 2>&1) ; RC=$?
ck "$RC" 0 "1a create succeeds"
ck "$(grep -c 'registry_add silver' "$TMP/calls")" 1 "1a the tier is registered once"
ckhas "$OUT" "created on osd.0 osd.1" "1a reports the tier"
cklacks "$OUT" "unwinding" "1a nothing was unwound"
ck "$(grep -cx silver "$TMP/pools")" 1 "1a the pool is there"
ck "$(grep -cx silver "$TMP/vtypes")" 1 "1a the volume type is there"

# ---- 1b. the registry edit fails: reported, and NOT unwound ----
# Everything before step 6 is consistent between Ceph and Cinder, so deleting a
# correct tier because a config apply failed destroys good work to no purpose.
# The repairable state is the better one: list flags it, re-running finishes it.
reset_cluster
REGISTRY_ADD_RC=1
OUT=$(ceph_device_tier_create silver 0 1 2>&1) ; RC=$?
ck "$RC" 1 "1b a failed registry edit returns non-zero"
ckhas "$OUT" "could not be" "1b says the registration did not happen"
ckhas "$OUT" "re-run" "1b says how to finish"
cklacks "$OUT" "unwinding" "1b did not unwind"
ck "$(grep -cx silver "$TMP/pools")" 1 "1b the pool is kept"
ck "$(grep -cx silver "$TMP/rules")" 1 "1b the rule is kept"
ck "$(grep -cx silver "$TMP/vtypes")" 1 "1b the volume type is kept"
ck "$(awk -F: '$2 == "silver"' "$TMP/classes" | wc -l | tr -d ' ')" 2 "1b both OSDs kept the class"

# ---- 1c. re-running after 1b completes the registration ----
# The same state 1b left behind, reached the way an operator would: every
# object exists, so create takes its idempotent branch -- which still has to
# register, or the failure in 1b would be permanent.
REGISTRY_ADD_RC=0
: > "$TMP/calls"
OUT=$(ceph_device_tier_create silver 0 1 2>&1) ; RC=$?
ck "$RC" 0 "1c re-running an existing tier succeeds"
ckhas "$OUT" "already exists" "1c says it already exists"
ck "$(grep -c 'registry_add silver' "$TMP/calls")" 1 "1c the idempotent branch registers"
ck "$(grep -c 'cinder.storage.tier' "$SETTINGS_TXT")" 2 "1c the registry now holds both tiers"
ck "$(grep -cx silver "$TMP/pools")" 1 "1c nothing was built a second time"

# ---- 1d. the idempotent branch reports a registry failure ----
REGISTRY_ADD_RC=1
OUT=$(ceph_device_tier_create silver 0 1 2>&1) ; RC=$?
ck "$RC" 1 "1d an existing tier that cannot be registered returns non-zero"
ckhas "$OUT" "is not registered" "1d says the backend is missing"

# ---- 1e. a create that fails earlier never reaches the registry ----
reset_cluster
DEAD_PAT='rule create-replicated'
OUT=$(ceph_device_tier_create silver 0 1 2>&1) ; RC=$?
ck "$RC" 1 "1e a failed rule create returns non-zero"
ck "$(grep -c registry_add "$TMP/calls")" 0 "1e the registry was never touched"
ckhas "$OUT" "unwinding" "1e the earlier steps were unwound"
ck "$(awk -F: '$2 == "silver"' "$TMP/classes" | wc -l | tr -d ' ')" 0 "1e no OSD kept the class"

# ==== ceph_device_tier_list: the two disagreements =======================

# ---- 2a. a tier on Ceph that is not registered ----
reset_cluster
: > "$SETTINGS_TXT"
OUT=$(ceph_device_tier_list 2>&1)
ckhas "$OUT" "not-registered" "2a flags a tier missing from the registry"
ck "$(echo "$OUT" | awk '$1 == "gold" { print $7 }')" "no" "2a the REGIST column says no"

# ---- 2b. a registry entry with nothing on the Ceph side ----
# This is the direction only the registry can show, and the one that has Cinder
# advertising a volume type whose pool does not exist.
reset_cluster
printf 'cinder.storage.tier.0.name = gold\ncinder.storage.tier.1.name = bronze\n' > "$SETTINGS_TXT"
OUT=$(ceph_device_tier_list 2>&1)
ckhas "$OUT" "registered-but-absent" "2b flags a registry entry with no tier"
ck "$(echo "$OUT" | awk '$1 == "bronze" { print $7 }')" "yes" "2b the absent tier is still shown as registered"
ck "$(echo "$OUT" | awk '$1 == "gold" { print $7 }')" "yes" "2b the real tier is registered"
cklacks "$(echo "$OUT" | grep '^gold')" "not-registered" "2b the real tier is not flagged"

# ---- 2c. an unreadable registry is unknown, not empty ----
# Printing not-registered against every tier because settings.txt could not be
# read sends the operator to re-run create on tiers that are registered.
reset_cluster
rm -f "$SETTINGS_TXT"
OUT=$(ceph_device_tier_list 2>&1)
ckhas "$OUT" "registry-unreadable" "2c says the registry could not be read"
ck "$(echo "$OUT" | awk '$1 == "gold" { print $7 }')" "?" "2c the REGIST column says unknown"
cklacks "$OUT" "not-registered" "2c does not claim the tier is unregistered"
cklacks "$OUT" "registered-but-absent" "2c invents no rows from a list it does not have"

# ---- 2d. an empty registry entry is the empty-list placeholder ----
# policy_ext_storage.cpp writes one back whenever the vector is empty, so it is
# how "no tiers" is encoded -- not a tier with no name.
reset_cluster
printf 'cinder.storage.tier.0.name = \n' > "$SETTINGS_TXT"
OUT=$(ceph_device_tier_list 2>&1)
ck "$(echo "$OUT" | grep -c 'registered-but-absent')" 0 "2d the placeholder is not a missing tier"
ck "$(echo "$OUT" | awk '$1 == "gold" { print $7 }')" "no" "2d and gold is genuinely unregistered"

# ==== the four queries the CLI validates against =========================
#
# Every one of these returns non-zero rather than an empty answer when it
# cannot read. That is the whole contract: cli_ceph.cpp refuses to create a
# tier when a query fails, and would otherwise accept a name it never checked.

# ---- 3a. names_taken lists all four kinds ----
reset_cluster
OUT=$(ceph_device_tier_names_taken) ; RC=$?
ck "$RC" 0 "3a names_taken succeeds"
ckhas "$OUT" "class|gold" "3a lists device classes"
ckhas "$OUT" "rule|replicated_rule" "3a lists CRUSH rules"
ckhas "$OUT" "pool|cinder-volumes" "3a lists pools"
ckhas "$OUT" "vtype|CubeStorage" "3a lists volume types"
ck "$(echo "$OUT" | grep -c '^class|$')" 0 "3a the classless OSD contributes no empty name"

# ---- 3b. each of the four reads failing is a refusal ----
for probe in 'osd crush class ls' 'osd crush rule ls' 'osd pool ls' ; do
    reset_cluster
    DEAD_PAT="^$probe\$"
    ceph_device_tier_names_taken >/dev/null 2>&1
    ck "$?" 1 "3b names_taken refuses when '$probe' fails"
done
reset_cluster
OS_DEAD=1
ceph_device_tier_names_taken >/dev/null 2>&1
ck "$?" 1 "3b names_taken refuses when the volume type list fails"

# ---- 3c. a read that succeeds and still answers nothing ----
# `ceph` exiting 0 with output jq cannot parse is an answer nobody got, and
# letting it fall through would hand the CLI a shorter list of taken names.
reset_cluster
fake_ceph_garbage() { case "$*" in 'osd crush class ls') echo 'not json' ; return 0 ;; esac ; fake_ceph "$@" ; }
CEPH_SAVE=$CEPH ; CEPH=fake_ceph_garbage
ceph_device_tier_names_taken >/dev/null 2>&1
ck "$?" 1 "3c unparseable class list is a refusal, not a short list"
CEPH=$CEPH_SAVE

# ---- 3d. the OSD table ----
reset_cluster
OUT=$(ceph_device_tier_osd_table) ; RC=$?
ck "$RC" 0 "3d osd_table succeeds"
ck "$(echo "$OUT" | grep -c '^')" 7 "3d one row per OSD"
ck "$(echo "$OUT" | grep '^2|')" "2|cube451|gold|up" "3d id, host, class and state"
ck "$(echo "$OUT" | grep '^4|')" "4|cube453||up" "3d an OSD with no class has an empty class field"
reset_cluster
DEAD_PAT='osd tree'
ceph_device_tier_osd_table >/dev/null 2>&1
ck "$?" 1 "3d an unreadable tree is a refusal"

# ---- 3e. which pools select through a class ----
# The empty answer and the unreadable one are different, and this is the query
# whose answer the CLI shows before asking for confirmation.
reset_cluster
ck "$(ceph_device_tier_class_users ssd)" "k8s-volumes" "3e finds the pool on a class-restricted rule"
ck "$(ceph_device_tier_class_users gold)" "gold" "3e finds the tier's own pool"
OUT=$(ceph_device_tier_class_users hdd) ; RC=$?
ck "$RC" 0 "3e a class no rule selects through is a successful empty answer"
ck "$OUT" "" "3e and the answer is empty"
reset_cluster
DEAD_PAT='osd crush rule dump'
ceph_device_tier_class_users ssd >/dev/null 2>&1
ck "$?" 1 "3e an unreadable rule dump is a refusal"
reset_cluster
DEAD_PAT='osd pool ls detail'
ceph_device_tier_class_users ssd >/dev/null 2>&1
ck "$?" 1 "3e an unreadable pool list is a refusal"

# ---- 3f. the device tier names, and which of them this CLI owns ----
#
# Ownership is the registry, never the shape of the Ceph objects. A device
# class with a same-named rule and pool is what a device tier looks like, and
# customers hand-build exactly that shape (#1335 lists computehdd / computessd
# / smarthealth on one site) -- so "looks like one" and "is one" have to come
# back as different answers, or the CLI ends up offering someone else's
# storage for deletion.
reset_cluster
printf 'cinder.storage.tier.0.name = gold\ncinder.storage.tier.1.name = bronze\n' > "$SETTINGS_TXT"
OUT=$(ceph_device_tier_names) ; RC=$?
ck "$RC" 0 "3f names succeeds"
ck "$(echo "$OUT" | sort | tr '\n' ',')" "registered|gold,registry-only|bronze," "3f registered and registry-only are told apart"

# ---- 3g. a Ceph structure the registry does not list is unmanaged ----
reset_cluster
: > "$SETTINGS_TXT"
ck "$(ceph_device_tier_names)" "unmanaged|gold" "3g an unregistered lookalike is not ours"

# ---- 3h. an unreadable registry is a refusal, not "nothing is ours" ----
# Answering "unmanaged" for everything because settings.txt could not be read
# would tell the CLI it owns none of these, which is not an answer anybody got.
reset_cluster
rm -f "$SETTINGS_TXT"
ceph_device_tier_names >/dev/null 2>&1
ck "$?" 1 "3h an unreadable registry refuses"

# ---- 3i. a registry entry is data, whatever bytes it holds ----
# The registry is written by the policy chain and by `hex_config commit
# <settings>` without going through the CLI's name guard, so an entry can hold
# any byte. Two of them are traps: a shell metacharacter, which the CLI must
# never let become a command, and a glob, which must not match every tier.
reset_cluster
printf 'cinder.storage.tier.0.name = bad; touch %s/marker\ncinder.storage.tier.1.name = *\n' \
    "$TMP" > "$SETTINGS_TXT"
OUT=$(ceph_device_tier_names) ; RC=$?
ck "$RC" 0 "3i names still succeeds"
ckhas "$OUT" "registry-only|bad; touch $TMP/marker" "3i the entry comes back verbatim"
ckhas "$OUT" "registry-only|*" "3i a glob entry comes back as itself"
ck "$(echo "$OUT" | grep -c '^registered|')" 0 "3i and the glob did not match gold"
ck "$(echo "$OUT" | grep -c '^unmanaged|gold$')" 1 "3i gold is unmanaged, not registered by a glob"
[ -e "$TMP/marker" ] && { fail=$((fail+1)); echo "FAIL: 3i the marker command must never run"; } || pass=$((pass+1))

# ==== the health gate (#840 WP-5) ========================================
#
# Requiring HEALTH_OK is not usable: measured on the 1cc, one BlueStore slow
# operation raises BLUESTORE_SLOW_OP_ALERT for 24 hours (warn_threshold 1,
# warn_lifetime 86400) while every PG is active+clean, and that blocked every
# device tier command for a day. What the gate refuses on is a replica or PG
# missing now, a failure domain down, or nowhere to put the data being moved.
# Everything else is reported and let through.

# ---- 4a. HEALTH_OK with nothing firing ----
reset_cluster
OUT=$(_ceph_device_tier_health_ok 2>&1) ; ck "$?" 0 "4a HEALTH_OK proceeds"
ck "$OUT" "" "4a and says nothing"

# ---- 4b. the slow-op family is a warning, not a refusal ----
reset_cluster
HEALTH_STATUS=HEALTH_WARN
HEALTH_CHECKS="BLUESTORE_SLOW_OP_ALERT SLOW_OPS"
OUT=$(_ceph_device_tier_health_ok 2>&1) ; ck "$?" 0 "4b a slow-op warning proceeds"
ckhas "$OUT" "BLUESTORE_SLOW_OP_ALERT" "4b names the check it let through"
ckhas "$OUT" "SLOW_OPS" "4b names both checks"
ckhas "$OUT" "going ahead" "4b says it is going ahead"
cklacks "$OUT" "Error" "4b is not an error"

# ---- 4c. redundancy checks refuse ----
for c in PG_AVAILABILITY PG_DEGRADED PG_DEGRADED_FULL PG_BACKFILL_FULL \
         OSD_DOWN OSD_HOST_DOWN OSD_FULL POOL_FULL MON_DOWN OBJECT_UNFOUND ; do
    reset_cluster
    HEALTH_STATUS=HEALTH_WARN
    HEALTH_CHECKS="$c"
    OUT=$(_ceph_device_tier_health_ok 2>&1)
    ck "$?" 1 "4c $c refuses"
done

# ---- 4d. a blocking check alongside a harmless one still refuses ----
reset_cluster
HEALTH_STATUS=HEALTH_WARN
HEALTH_CHECKS="SLOW_OPS PG_DEGRADED OSDMAP_FLAGS"
OUT=$(_ceph_device_tier_health_ok 2>&1) ; ck "$?" 1 "4d one blocking check is enough"
ckhas "$OUT" "PG_DEGRADED" "4d names the blocking check"
cklacks "$OUT" "going ahead" "4d does not claim it went ahead"

# ---- 4e. the standing-property warnings are deliberately not blocking ----
# Blocking on these would rebuild the trap this change exists to remove: they
# describe how a cluster is configured or filled and do not clear on their own.
reset_cluster
HEALTH_STATUS=HEALTH_WARN
HEALTH_CHECKS="POOL_NO_REDUNDANCY OSD_NEARFULL POOL_NEARFULL OSDMAP_FLAGS RECENT_CRASH"
OUT=$(_ceph_device_tier_health_ok 2>&1) ; ck "$?" 0 "4e standing warnings proceed"
ckhas "$OUT" "POOL_NO_REDUNDANCY" "4e still reports them"

# ---- 4f. an unrecognised check is warned about, not blocked ----
reset_cluster
HEALTH_STATUS=HEALTH_WARN
HEALTH_CHECKS="SOME_FUTURE_CHECK"
OUT=$(_ceph_device_tier_health_ok 2>&1) ; ck "$?" 0 "4f an unknown check proceeds"
ckhas "$OUT" "SOME_FUTURE_CHECK" "4f and is named"

# ---- 4g. HEALTH_ERR is the backstop for everything unrecognised ----
# An error-level check refuses whatever its name is, so an unknown severe
# condition still stops here even though unknown warnings do not.
reset_cluster
HEALTH_STATUS=HEALTH_ERR
HEALTH_CHECKS="SOME_FUTURE_CHECK"
OUT=$(_ceph_device_tier_health_ok 2>&1) ; ck "$?" 1 "4g HEALTH_ERR refuses on any check"
ckhas "$OUT" "HEALTH_ERR" "4g says why"
ckhas "$OUT" "SOME_FUTURE_CHECK" "4g names what is firing"

# ---- 4h. active recovery still refuses ----
reset_cluster
RECOVERING=42
OUT=$(_ceph_device_tier_health_ok 2>&1) ; ck "$?" 1 "4h recovery in progress refuses"
ckhas "$OUT" "while ceph is recovering" "4h keeps the pre-existing reason"

# ---- 4i. a name matched whole, not as a substring ----
reset_cluster
HEALTH_STATUS=HEALTH_WARN
HEALTH_CHECKS="PG_DEGRADED_SOMETHING_ELSE"
OUT=$(_ceph_device_tier_health_ok 2>&1) ; ck "$?" 0 "4i PG_DEGRADED_SOMETHING_ELSE is not PG_DEGRADED"

# ---- 4j. an unreadable or unparseable status is unknown, never OK ----
reset_cluster
DEAD_PAT='^-s -f json$'
OUT=$(_ceph_device_tier_health_ok 2>&1) ; ck "$?" 1 "4j an unreadable status refuses"
ckhas "$OUT" "cannot read ceph status" "4j says why"
reset_cluster
ceph_garbage() { case "$*" in '-s -f json') echo 'not json' ; return 0 ;; esac ; fake_ceph "$@" ; }
CEPH=ceph_garbage
OUT=$(_ceph_device_tier_health_ok 2>&1) ; ck "$?" 1 "4k an unparseable status refuses"
ckhas "$OUT" "could not be parsed" "4k says why"
CEPH=fake_ceph

# ---- 4l. end to end: create runs with only a slow-op warning firing ----
# The behaviour change, at the level an operator meets it.
reset_cluster
HEALTH_STATUS=HEALTH_WARN
HEALTH_CHECKS="BLUESTORE_SLOW_OP_ALERT"
OUT=$(ceph_device_tier_create silver 0 1 2>&1) ; RC=$?
ck "$RC" 0 "4l create proceeds under a slow-op warning"
ckhas "$OUT" "created on osd.0 osd.1" "4l and builds the tier"
ck "$(grep -c 'registry_add silver' "$TMP/calls")" 1 "4l and registers it"

# ---- 4m. end to end: create refuses with a degraded PG ----
reset_cluster
HEALTH_STATUS=HEALTH_WARN
HEALTH_CHECKS="PG_DEGRADED"
OUT=$(ceph_device_tier_create silver 0 1 2>&1) ; RC=$?
ck "$RC" 1 "4m create refuses while a PG is degraded"
ck "$(grep -c registry_add "$TMP/calls")" 0 "4m and touched nothing"
ck "$(awk -F: '$2 == "silver"' "$TMP/classes" | wc -l | tr -d ' ')" 0 "4m no OSD changed class"

echo "----"; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: device tier registry, list and CLI queries"; exit 0; } || exit 1
