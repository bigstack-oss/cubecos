# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

CUBE_NODE_LIST_JSON=$(cubectl node list -j)
CUBE_NODE_CONTROL_JSON=$(cubectl node list -j -r control)
CUBE_NODE_COMPUTE_JSON=$(cubectl node list -j -r compute)
CUBE_NODE_STORAGE_JSON=$(cubectl node list -j -r storage)
CUBE_NODE_LIST_IPS=($(cubectl node list | cut -d"," -f2))
CUBE_NODE_MANAGEMENT_IP=$(echo $CUBE_NODE_LIST_JSON | jq .[].ip | jq -r .management | grep -v null)
CUBE_NODE_PROVIDER_IP=$(echo $CUBE_NODE_LIST_JSON | jq .[].ip | jq -r .provider | grep -v null)
CUBE_NODE_OVERLAY_IP=$(echo $CUBE_NODE_LIST_JSON | jq .[].ip | jq -r .overlay | grep -v null)
CUBE_NODE_STORAGE_IP=$(echo $CUBE_NODE_LIST_JSON | jq .[].ip | jq -r .storage | grep -v null)
CUBE_NODE_CLUSTER_IP=$(echo $CUBE_NODE_LIST_JSON | jq .[].ip | jq -r ".[\"storage-cluster\"] // empty" | grep -v null)
CUBE_NODE_LIST_HOSTNAMES=($(echo $CUBE_NODE_LIST_JSON | jq -r .[].hostname))
CUBE_NODE_CONTROL_HOSTNAMES=($(echo $CUBE_NODE_CONTROL_JSON | jq -r .[].hostname))
CUBE_NODE_COMPUTE_HOSTNAMES=($(echo $CUBE_NODE_COMPUTE_JSON | jq -r .[].hostname))
CUBE_NODE_STORAGE_HOSTNAMES=($(echo $CUBE_NODE_STORAGE_JSON | jq -r .[].hostname))
INFLUX="timeout $SRVTO /usr/bin/influx -host $(shared_id)"
