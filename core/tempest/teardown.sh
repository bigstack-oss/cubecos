#!/bin/bash
# Delete what this run left: resources of tempest-* projects created during the run, then this run's fixtures.
set -u
: "${OUT:?}"
os() { openstack "$@" 2>>"$OUT/teardown.log"; }
tp=$(os project list -f value -c ID -c Name | awk '$2 ~ /^tempest-/ {print $1}' | grep -vxFf "$OUT/projects-before.txt")
mine() { grep -qxF "$1" <<<"$tp"; }

lbs() { os loadbalancer list -f value -c id -c project_id | while read -r id p; do mine "$p" && echo "$id"; done; }
if [ -n "$tp" ]; then
    for lb in $(lbs); do os loadbalancer delete --cascade "$lb"; done
    for _ in $(seq 60); do [ -z "$(lbs)" ] && break; sleep 10; done
    shares=$(os share list --all-projects -f value -c ID -c "Project ID" | while read -r id p; do mine "$p" && echo "$id"; done)
    for s in $shares; do os share delete --force "$s"; done
    [ -n "$shares" ] && sleep 30
    for sn in $(os share network list --all-projects -f value -c ID -c "Project ID" | while read -r id p; do mine "$p" && echo "$id"; done); do
        os share network delete "$sn"; done
fi
for p in $tp; do
    # left by an interrupted run; tempest deletes these itself otherwise
    for v in $(os server list --all-projects --project "$p" -f value -c ID); do os server delete --wait "$v"; done
    for f in $(os floating ip list --project "$p" -f value -c ID); do os floating ip delete "$f"; done
    for v in $(os volume snapshot list --all-projects --project "$p" -f value -c ID); do os volume snapshot delete --force "$v"; done
    for v in $(os volume list --all-projects --project "$p" -f value -c ID); do os volume delete --force "$v"; done
    for r in $(os router list --project "$p" -f value -c ID); do
        for port in $(os port list --router "$r" --device-owner network:router_interface -f value -c ID); do os router remove port "$r" "$port"; done
        os router unset --external-gateway "$r"; os router delete "$r"; done
    for port in $(os port list --project "$p" -f value -c ID -c device_owner | awk '$2 !~ /^network:/ {print $1}'); do
        os port delete "$port"; done
    for n in $(os network list --project "$p" -f value -c ID); do os network delete "$n"; done
    for g in $(os security group list --project "$p" -f value -c ID); do os security group delete "$g"; done
    for u in $(os user list --project "$p" -f value -c ID); do os user delete "$u"; done
    os project delete "$p"
done
# flavors have no project: tempest-* ones that appeared during the run
for f in $(os flavor list --all -f value -c ID -c Name | awk '$2 ~ /^tempest-/ {print $1}' | grep -vxFf "$OUT/flavors-before.txt"); do
    os flavor delete "$f"; done
[ -f "$OUT/created.txt" ] && while read -r kind id; do
    case $kind in
        router)  for port in $(os port list --router "$id" --device-owner network:router_interface -f value -c ID); do os router remove port "$id" "$port"; done
                 os router unset --external-gateway "$id"; os router delete "$id" ;;
        network) os network delete "$id" ;;
        image)   os image delete "$id" ;;
    esac
done < "$OUT/created.txt"
echo "teardown: $(wc -w <<<"$tp") tempest projects, $(wc -l < "$OUT/created.txt") fixtures; tempest-* projects left: $(os project list -f value -c Name | grep -c '^tempest-')"
