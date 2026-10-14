#!/bin/bash
#
# os_instance_list_for_project_long_run runs every 5 minutes on each control
# (glance_export_sync cron). Handing `server list --project` a project name
# makes the client GET /v3/projects/<name> first, which keystone answers 404
# and logs as ProjectNotFound -- once per project per run per control
# (cubecos#2065). It has to pass the id; the cached JSON stays keyed by name.
#
#   Run: bash test_os_instance_list_for_project_by_id.sh
#
set -u
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
SRC=$(dirname "${BASH_SOURCE[0]}")/../modules/sdk_os.sh
sed -n '/^os_instance_list_for_project_long_run()/,/^}/p' $SRC \
    | sed "s|/tmp/instance_for_project.json|$T/out.json|" > $T/fn.sh
source $T/fn.sh
[ "$(type -t os_instance_list_for_project_long_run)" = function ] || { echo "FAIL: function not extracted"; exit 1; }

pass=0 fail=0
chk(){ # description actual expected
    if [ "$2" = "$3" ] ; then
        pass=$((pass+1)); printf 'PASS %-40s -> %s\n' "$1" "$2"
    else
        fail=$((fail+1)); printf 'FAIL %-40s -> got "%s", want "%s"\n' "$1" "$2" "$3"
    fi
}

# `project list -f value` prints "<id> <name>"; `server list` records its --project
openstack_stub(){
    case "$1 $2" in
        "project list")
            printf '%s\n' "3d4701dd99b342cb9b2ede9219c61c34 appfw2-cmp211-110" \
                          "52f53252b73c408eafa145043271405c admin" \
                          "0b3e5c1d2f4a4b6c8d9e0f1a2b3c4d5e service" ;;
        "server list")
            local p=""
            while [ $# -gt 0 ] ; do [ "$1" = --project ] && p=$2 ; shift ; done
            echo "$p" >> $T/projects
            echo "[{\"Name\": \"vm-of-$p\"}]" ;;
    esac
}
OPENSTACK=openstack_stub

os_instance_list_for_project_long_run
chk "--project gets ids" "$(paste -sd, $T/projects)" "3d4701dd99b342cb9b2ede9219c61c34,52f53252b73c408eafa145043271405c"
chk "JSON keyed by name" "$(jq -c 'keys' $T/out.json)" '["admin","appfw2-cmp211-110","service"]'
chk "name key holds that id's servers" "$(jq -r '.admin[0].Name' $T/out.json)" "vm-of-52f53252b73c408eafa145043271405c"

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
