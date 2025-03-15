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

opensearch-dashboards_ops_reqid_search()
{
    local saved_objects="$($CURL -X GET "http://localhost:5601/opensearch-dashboards/api/saved_objects/_find?type=search")"
    echo $saved_objects | grep -q ops-reqid-search || $CURL -X POST "http://localhost:5601/opensearch-dashboards/api/saved_objects/_import?overwrite=true" -H "osd-xsrf:true" --form file=@/etc/opensearch-dashboards/export.ndjson
}
