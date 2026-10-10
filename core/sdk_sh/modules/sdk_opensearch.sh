# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

opensearch_stats()
{
    $CURL http://localhost:9200/_cluster/health | jq -r .
    printf "\n"
}

opensearch_index_list()
{
    $CURL http://localhost:9200/_cat/indices?v
    printf "\n"
}

opensearch_index_curator()
{
    local rp=${1:-14}
    local dryrun=$2
    /usr/local/bin/curator_cli --host localhost --port 9200 $dryrun delete-indices --filter_list "[{\"filtertype\":\"age\",\"source\":\"name\",\"direction\":\"older\",\"unit\":\"days\",\"unit_count\":$rp,\"timestring\":\"%Y%m%d\"}]" || true
}

# Paths named, not inlined: the tests point them somewhere writable.
OPENSEARCH_URL=${OPENSEARCH_URL:-http://localhost:9200}
OPENSEARCH_STATE_DIR=${OPENSEARCH_STATE_DIR:-/etc/appliance/state}

# True when this node sees an elected cluster manager. Local state only, so it never
# waits on an election the way a cluster-manager request does (~30s, then 503).
opensearch_has_manager()
{
    $CURL -s -m 5 "$OPENSEARCH_URL/_cluster/state/cluster_manager_node?local=true" 2>/dev/null | jq -e '.cluster_manager_node // empty' >/dev/null 2>&1
}

# Wait up to $1 seconds (default 0) for an elected cluster manager.
opensearch_wait_manager()
{
    local secs=${1:-0}
    local i=0
    while ! opensearch_has_manager ; do
        [ $i -ge $secs ] && return 1
        sleep 5
        i=$((i + 5))
    done
    return 0
}

# Returns 2 without a cluster manager; config_opensearch re-applies at cluster_start.
opensearch_shard_per_node_set()
{
    local shard=$1
    if ! opensearch_has_manager ; then
        Warning "opensearch has no cluster manager yet, defer max_shards_per_node"
        return 2
    fi
    $CURL -s -m 30 -XPUT "$OPENSEARCH_URL/_cluster/settings?cluster_manager_timeout=10s" -H 'Content-type: application/json' --data-binary $"{\"persistent\":{\"cluster.max_shards_per_node\":$shard}}"
}

# Delete only indices that are unrecoverable: a primary with no valid copy on any node.
# Unassigned replicas, or primaries whose holder is just down, reallocate on their own.
opensearch_shard_delete_unassigned()
{
    local url=http://localhost:9200

    if is_cluster_rolling ; then
        Warning "cluster is rolling, skip deleting unassigned opensearch indices"
        return 0
    fi

    if ! opensearch_has_manager ; then
        Warning "opensearch has no cluster manager yet, skip deleting unassigned indices"
        return 0
    fi

    # a missing node may hold the only copy
    local expected=$(grep '^discovery.zen.ping.unicast.hosts:' /etc/opensearch/opensearch.yml 2>/dev/null | grep -o '"[^"]*"' | wc -l)
    [ "${expected:-0}" -gt 0 ] || expected=1
    local nodes=$($CURL -s "$url/_cluster/health" | jq -r '.number_of_data_nodes // 0' 2>/dev/null)
    if [ "${nodes:-0}" -lt "$expected" ] ; then
        Warning "opensearch has ${nodes:-0}/$expected data nodes, skip deleting unassigned indices"
        return 0
    fi

    local index shard prirep state reason
    local doomed=""
    while read -r index shard prirep state ; do
        [ "$prirep" = "p" -a "$state" = "UNASSIGNED" ] || continue
        echo " $doomed " | grep -q " $index " && continue
        reason=$($CURL -s -XGET "$url/_cluster/allocation/explain" -H 'Content-type: application/json' \
                 --data-binary "{\"index\":\"$index\",\"shard\":$shard,\"primary\":true}" | jq -r '.can_allocate // ""' 2>/dev/null)
        [ "$reason" = "no_valid_shard_copy" ] && doomed+="$index "
    done < <($CURL -s "$url/_cat/shards?h=index,shard,prirep,state")

    for index in $doomed ; do
        Warning "deleting opensearch index $index: primary shard has no valid copy"
        $CURL -s -XDELETE "$url/$index" >/dev/null
    done
}

# Install an index template, or re-apply it when the file changed since the last install
# from this node (md5 kept in $OPENSEARCH_STATE_DIR). Waits up to $3 seconds (default 0)
# for a cluster manager, then returns 2 so the caller can defer: on a cold boot the
# master's commit runs before any peer's opensearch is up, and every cluster-manager
# request would wait ~30s and 503.
opensearch_template_install()
{
    local name=$1
    local file=$2
    local wait=${3:-0}
    local url="$OPENSEARCH_URL/_template/${name}"
    local stamp="$OPENSEARCH_STATE_DIR/opensearch_template_${name}"

    [ -r "$file" ] || { Warning "no such template file: $file" ; return 1 ; }
    local sum=$(md5sum < "$file" | cut -d' ' -f1)

    # unchanged: done, unless the cluster is up and says the template is gone
    if [ "$(cat "$stamp" 2>/dev/null)" = "$sum" ] ; then
        opensearch_has_manager || return 0
        [ "$($CURL -s -m 5 -o /dev/null -w '%{http_code}' "$url?local=true")" = "404" ] || return 0
    fi

    if ! opensearch_wait_manager $wait ; then
        Warning "opensearch has no cluster manager yet, defer template $name"
        return 2
    fi

    local i
    for i in 1 2 3 ; do
        if $CURL -sf -m 30 -X PUT "$url?cluster_manager_timeout=10s" \
                 -H 'Content-type: application/json' --data-binary "@${file}" >/dev/null 2>&1 ; then
            echo "$sum" > "$stamp"
            return 0
        fi
        sleep 5
    done

    Warning "failed to install opensearch template: $name"
    return 1
}

opensearch_ops_reqid_search()
{
    local saved_objects="$($CURL -X GET \"http://localhost:5601/opensearch-dashboards/api/saved_objects/_find?type=search\" 2>/dev/null)"
    echo $saved_objects | grep -q ops-reqid-search || $CURL -X POST "http://localhost:5601/opensearch-dashboards/api/saved_objects/_import?overwrite=true" -H "osd-xsrf:true" --form file=@/etc/opensearch-dashboards/export.ndjson 2>/dev/null
}

opensearch_ops_reqid_url()
{
    local reqid=${1:-NOSUCHREQID}
    local last=${2:-7d}
    local title="ops-reqid-search"
    local id="7f32d630-0275-11ec-8ec6-0d4cf465bb19"
    local message="req-"
    local template_ndjson=/etc/opensearch-dashboards/export.ndjson
    local new_ndjson=/tmp/${reqid}.ndjson
    local ops_url="http://$(shared_ip):5601/opensearch-dashboards"

    echo "${reqid}" | grep -q "^req[-]" || Error "bad req-id: ${reqid}"

    if ! ( $CURL -X GET "${ops_url}/api/saved_objects/_find?type=search" 2>/dev/null | jq -r .saved_objects[].id | grep -q "${reqid}" ) ; then
        sed -e "s/$title/$reqid/" -e "s/$id/$reqid/" -e "s/$message/$reqid/" $template_ndjson > $new_ndjson
        Quiet -n $CURL -X POST "${ops_url}/api/saved_objects/_import?overwrite=true" -H "osd-xsrf:true" --form file=@${new_ndjson}
        rm -f $new_ndjson
    fi

    idx_id=$($CURL -X GET "${ops_url}/api/saved_objects/_find?type=search" 2>/dev/null | jq -r .saved_objects[].references[].id | sort -u | head -1)

    local url="${ops_url}/app/data-explorer/discover/#/view/${reqid}"
    url+="?_a=(discover:(columns:!(agent_host,path,message),isDirty:!f,savedSearch:${reqid},sort:!(!(occurred_at,asc))),metadata:(indexPattern:'${idx_id}',view:discover))&_g=(filters:!(),refreshInterval:(pause:!t,value:0),time:(from:now-${last},to:now))"
    echo "$url"
}
