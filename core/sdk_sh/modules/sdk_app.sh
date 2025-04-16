# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

app_framework_uninstall()
{
    export PROJECT_NAME="app-framework"

    Quiet -n app_project_delete $PROJECT_NAME
}

# Deploy essential charts on app-framework
app_framework_deploy()
{
    local loadbalancer_ip=$1
    local tmpdir=$(mktemp -d -t appfw.XXXXXXXX)
    local kubeconfig="$tmpdir/kubeconfig"
    local timeout=900
    local elapsed=0

    while true ; do
        local state=$(sudo /usr/local/bin/rancher cluster ls 2>/dev/null | grep -w app-framework | awk '{print $2}')
        [ "$state" == "active" ] && break

        if [ $elapsed -ge $timeout ] ; then
            echo "Timed out!!!" 
            return 1
        fi

        sleep 30
        echo "Waiting for cluster to be active. State: $state. Time elapsed: $((elapsed+=30)) secs"
    done

    echo "Cluster is active. Deploying essential workloads"

    sudo /usr/local/bin/rancher cluster kf app-framework 2>/dev/null > $kubeconfig
    sudo chmod 0600 $kubeconfig

    # Cloud Provider Openstack
    helm --kubeconfig=$kubeconfig --kube-insecure-skip-tls-verify=true install openstack-ccm /opt/rancher/cpo/openstack-cloud-controller-manager-*.tgz -n kube-system -f - << EOF
secret:
  create: true
  name: cloud-config
cloudConfig:
  global:
    auth-url: $OS_AUTH_URL
    tenant-name: $PROJECT_NAME
    username: $PROJECT_NAME
    password: $PROJECT_PASSWORD
    region: RegionOne
    domain-name: default
  loadBalancer:
    floating-network-id: $FLOATING_NETWORK_ID
    subnet-id: $SUBNET_ID
  blockStorage:
    ignore-volume-az: true
EOF

    # Cinder CSI
    helm --kubeconfig=$kubeconfig --kube-insecure-skip-tls-verify=true install cinder-csi /opt/rancher/cpo/openstack-cinder-csi-*.tgz -n kube-system -f - << EOF
secret:
  enabled: true
  name: cloud-config
storageClass:
  enabled: false
  custom: |-
    ---
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      annotations:
        storageclass.kubernetes.io/is-default-class: "true"
      name: csi-cinder
    provisioner: cinder.csi.openstack.org
    allowVolumeExpansion: true
EOF

    # Load Balancer Service
    kubectl --kubeconfig=$kubeconfig --insecure-skip-tls-verify=true apply -f - << EOF
apiVersion: v1
kind: Service
metadata:
  name: ingress-lb
  namespace: ingress-nginx
spec:
  loadBalancerIP: "$loadbalancer_ip"
  ports:
  - name: https
    port: 443
    protocol: TCP
    targetPort: 443
  selector:
    app: ingress-nginx 
  type: LoadBalancer
EOF

    # Deploy app-framework core services
    tar -xzf /opt/appfw/appfw.tgz -C $tmpdir
    (cd $tmpdir && KUBECONFIG=$kubeconfig ./deploy.sh install)

    # FIXME: deploy ingress LoadBalancer service
    # kubectl --insecure-skip-tls-verify --kubeconfig $kubeconfig apply -f /opt/appfw/yaml/ingress-nginx.yaml

    rm -rf $tmpdir
}

app_framework_prerequisite()
{
    if [ $($OPENSTACK image list --name=rancher-cluster-image -f json | jq length) -eq 0 ] ; then
        echo "rancher-cluster-image is not imported"
        return 1
    fi
    if [ $($OPENSTACK image list --name=amphora-x64-haproxy -f json | jq length) -eq 0 ] ; then
        echo "Octavia Amphora is not imported"
        return 1
    fi

    return 0
}

# params:
# $1: MGMT_NETWORK
# $2: PUB_NETWORK
app_framework_install()
{
    app_framework_prerequisite || return 1

    export PROJECT_NAME="app-framework"
    export MGMT_NETWORK=${1:-public}
    export PUB_NETWORK=${2:-public}
    export LOADBALANCER_IP=$3
    export PROJECT_PASSWORD=$(echo -n $PROJECT_NAME | openssl dgst -sha1 -hmac cube2022 | awk '{print $2}')
    export RANCHER_TOKEN=$($TERRAFORM_CUBE state pull | jq -r '.resources[] | select(.type == "rancher2_bootstrap").instances[0].attributes.token')
    export CUBE_CONTROLLER=$(kubectl get endpoints | grep '^cube-controller' | awk '{print $2}')
    local appfw_pth=/opt/appfw

    sudo $HEX_SDK  os_create_project $PROJECT_NAME $MGMT_NETWORK $PUB_NETWORK

    local mgmt_network_id=$($OPENSTACK network list --project admin -f value -c ID -c Name | grep $MGMT_NETWORK | cut -d' ' -f1)
    $OPENSTACK network set --tag APPFW_MGMT_NET $mgmt_network_id

    export SUBNET_ID=$($OPENSTACK subnet list --project $PROJECT_NAME -f json |  jq -r '.[] | select(.Name=="private-k8s_subnet") | .ID')
    export FLOATING_NETWORK_ID=$($OPENSTACK network list --external -f json |  jq -r ".[] | select(.Name==\"$PUB_NETWORK\") | .ID")
    export ROUTER_ID=$($OPENSTACK router list --project $PROJECT_NAME -f json | jq -r ".[] | select(.Name==\"$PUB_NETWORK\") | .ID")

    Quiet -n $OPENSTACK flavor create --vcpus 2 --ram 4096 --disk 200 --public appfw.medium
    Quiet -n $OPENSTACK flavor create --vcpus 4 --ram 8192 --disk 200 --public appfw.large

    local rancher_file="/root/.rancher/cli2.json"
    cp -f ${rancher_file} ${rancher_file}.bak &&  jq '.Servers.rancherDefault.project = ""' ${rancher_file}.bak > ${rancher_file}
    if ! sudo /usr/local/bin/rancher cluster ls 2>/dev/null | grep $PROJECT_NAME
    then
        echo "Installing app-framework cluster"
        $appfw_pth/bin/rancher_client.py create_cluster
    fi

    app_framework_deploy $LOADBALANCER_IP
}

app_import()
{
    local app_pigz=$1
    local skip_flag=$2
    if [ ! -f "$app_pigz" ] ; then
        echo "usage: $0 ${FUNCNAME[0]} /mnt/cephfs/update/app-1.2.3.pigz [skip_flavor]"
        exit 1
    fi

    local tmpdir=$(mktemp -d -t $(basename $app_pigz).XXXXXXXX)
    tar -I pigz -xf $app_pigz -C $tmpdir

    (cd $tmpdir && ./import.sh $skip_flag) || true

    rm -rf $tmpdir
}

# params:
# $1: PROJECT_NAME
# $2: MGMT_NETWORK
# $3: PUB_NETWORK
app_project_create()
{
    export PROJECT_NAME=$1
    export MGMT_NETWORK=${2:-public}
    export PUB_NETWORK=${3:-public}
    export PROJECT_PASSWORD=$(echo -n $PROJECT_NAME | openssl dgst -sha1 -hmac cube2022 | awk '{print $2}')
    export RANCHER_TOKEN=$($TERRAFORM_CUBE state pull | jq -r '.resources[] | select(.type == "rancher2_bootstrap").instances[0].attributes.token')
    local appfw_pth=/opt/appfw

    sudo $HEX_SDK os_create_project $PROJECT_NAME $MGMT_NETWORK $PUB_NETWORK
    export SUBNET_ID=$($OPENSTACK subnet list --project $PROJECT_NAME -f json |  jq -r '.[] | select(.Name=="private-k8s_subnet") | .ID')
    export FLOATING_NETWORK_ID=$($OPENSTACK network list --external -f json |  jq -r ".[] | select(.Name==\"$PUB_NETWORK\") | .ID")
    export ROUTER_ID=$($OPENSTACK router list --project $PROJECT_NAME -f json | jq -r ".[] | select(.Name==\"$PUB_NETWORK\") | .ID")

    $appfw_pth/bin/rancher_client.py create_templates
}

app_project_delete()
{
    export PROJECT_NAME=$1
    export RANCHER_TOKEN=$($TERRAFORM_CUBE state pull | jq -r '.resources[] | select(.type == "rancher2_bootstrap").instances[0].attributes.token')
    local appfw_pth=/opt/appfw

    # FIXME: delete all clusters in the project
    $appfw_pth/bin/rancher_client.py delete_cluster || true

    $appfw_pth/bin/rancher_client.py delete_templates || true
    $HEX_SDK os_purge_project -y $PROJECT_NAME || true
    Quiet -n $OPENSTACK -v user delete $PROJECT_NAME
}
