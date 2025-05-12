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

opensearch_shard_per_node_set()
{
    local shard=$1
    $CURL -XPUT http://localhost:9200/_cluster/settings -H 'Content-type: application/json' --data-binary $"{\"persistent\":{\"cluster.max_shards_per_node\":$shard}}"
}

opensearch_shard_delete_unassigned()
{
    $CURL -XGET http://localhost:9200/_cat/shards?h=index,shard,prirep,state,unassigned.reason| grep UNASSIGNED | cut -d' ' -f1  | xargs -i $CURL -XDELETE "http://localhost:9200/{}"
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
    local vip=$($HEX_SDK -f json health_vip_report | jq -r .description | cut -d"/" -f1)
    [ "x$vip" != "xnon-HA" ] || vip=$(echo -e "$CUBE_NODE_MANAGEMENT_IP" | head -1)
    local ops_url="http://${vip}:5601/opensearch-dashboards"

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
