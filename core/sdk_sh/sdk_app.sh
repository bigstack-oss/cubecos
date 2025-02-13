# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ]; then
    echo "Error: PROG not set" >&2
    exit 1
fi

if [ -f /etc/admin-openrc.sh  ]; then
    . /etc/admin-openrc.sh
fi

app_framework_uninstall()
{
    export PROJECT_NAME="app-framework"
    # export RANCHER_TOKEN=$(/usr/local/bin/terraform-cube.sh state pull | jq -r '.resources[] | select(.type == "rancher2_bootstrap").instances[0].attributes.token')

    # local CUBECONTROLLER=$(hex_sdk health_vip_report | cut -d'/' -f1)
    # if [ "$CUBECONTROLLER" = "non-HA" ]; then
    #     CUBECONTROLLER=$(cubectl node list -r control | cut -d',' -f2)
    # fi
    # CONTEXT=$(echo yes | sudo /usr/local/bin/rancher login --token $RANCHER_TOKEN https://${CUBECONTROLLER}:10443 2>/dev/null | grep local | grep Default | awk '{print $3}')
    # sudo /usr/local/bin/rancher context switch $CONTEXT 2>/dev/null

    # local APPFW_PTH=/opt/appfw
    # local KUBECONFIG="/tmp/${PROJECT_NAME}.kubeconfig"
    # sudo /usr/local/bin/rancher cluster kf ${PROJECT_NAME} 2>/dev/null > $KUBECONFIG

    # helm --kubeconfig $KUBECONFIG delete docker-registry -n docker-registry 2>/dev/null || true
    # helm --kubeconfig $KUBECONFIG delete chartmuseum -n chartmuseum 2>/dev/null || true
    # helm --kubeconfig $KUBECONFIG delete keycloak -n keycloak 2>/dev/null || true
    # Note: keycloak namespace should not be deleted
    # sudo /usr/local/bin/rancher namespace delete docker-registry 2>/dev/null || true
    # sudo /usr/local/bin/rancher namespace delete chartmuseum 2>/dev/null || true
    # sudo /usr/local/bin/rancher namespace delete keycloak 2>/dev/null || true

    app_project_delete $PROJECT_NAME || true
}

# Deploy essential charts on app-framework
app_framework_deploy()
{
    local LOADBALANCER_IP=$1
    local TMPDIR=$(mktemp -d -t appfw.XXXXXXXX)
    local KUBECONFIG="$TMPDIR/kubeconfig"
    local TIMEOUT=900
    local ELAPSED=0

    while true; do
        local state=$(sudo /usr/local/bin/rancher cluster ls 2>/dev/null | grep -w app-framework | awk '{print $2}')
        [ "$state" == "active" ] && break

        if [ $ELAPSED -ge $TIMEOUT ]; then
            echo "Timed out!!!" 
            return 1
        fi

        sleep 30
        echo "Waiting for cluster to be active. State: $state. Time elapsed: $((ELAPSED+=30)) secs"
    done

    echo "Cluster is active. Deploying essential workloads"

    sudo /usr/local/bin/rancher cluster kf app-framework 2>/dev/null > $KUBECONFIG
    sudo chmod 0600 $KUBECONFIG

    # Cloud Provider Openstack
    helm --kubeconfig=$KUBECONFIG --kube-insecure-skip-tls-verify=true install openstack-ccm /opt/rancher/cpo/openstack-cloud-controller-manager-*.tgz -n kube-system -f - << EOF
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
    helm --kubeconfig=$KUBECONFIG --kube-insecure-skip-tls-verify=true install cinder-csi /opt/rancher/cpo/openstack-cinder-csi-*.tgz -n kube-system -f - << EOF
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
    kubectl --kubeconfig=$KUBECONFIG --insecure-skip-tls-verify=true apply -f - << EOF
apiVersion: v1
kind: Service
metadata:
  name: ingress-lb
  namespace: ingress-nginx
spec:
  loadBalancerIP: "$LOADBALANCER_IP"
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
    tar -xzf /opt/appfw/appfw.tgz -C $TMPDIR
    (cd $TMPDIR && KUBECONFIG=$KUBECONFIG ./deploy.sh install)

    # FIXME: deploy ingress LoadBalancer service
    # kubectl --insecure-skip-tls-verify --kubeconfig $KUBECONFIG apply -f /opt/appfw/yaml/ingress-nginx.yaml

    rm -rf $TMPDIR
}

app_framework_prerequisite()
{
    if [ $(openstack image list --name=rancher-cluster-image -f json | jq length) -eq 0 ]; then
        echo "rancher-cluster-image is not imported"
        return 1
    fi
    if [ $(openstack image list --name=amphora-x64-haproxy -f json | jq length) -eq 0 ]; then
        echo "Octavia Amphora is not imported"
        return 1
    fi

    return 0
}

# params:
# $1: mgmt_network
# $2: pub_network
app_framework_install()
{
    app_framework_prerequisite || return 1

    export PROJECT_NAME="app-framework"
    export MGMT_NETWORK=${1:-public}
    export PUB_NETWORK=${2:-public}
    export LOADBALANCER_IP=$3
    export PROJECT_PASSWORD=$(echo -n $PROJECT_NAME | openssl dgst -sha1 -hmac cube2022 | awk '{print $2}')
    export RANCHER_TOKEN=$(/usr/local/bin/terraform-cube.sh state pull | jq -r '.resources[] | select(.type == "rancher2_bootstrap").instances[0].attributes.token')
    export CUBE_CONTROLLER=$(kubectl get endpoints | grep '^cube-controller' | awk '{print $2}')
    local APPFW_PTH=/opt/appfw

    sudo hex_sdk os_create_project $PROJECT_NAME $MGMT_NETWORK $PUB_NETWORK

    MGMT_NETWORK_ID=$(openstack network list --project admin -f value -c ID -c Name | grep $MGMT_NETWORK | cut -d' ' -f1)
    openstack network set --tag APPFW_MGMT_NET $MGMT_NETWORK_ID

    export SUBNET_ID=$(openstack subnet list --project $PROJECT_NAME -f json |  jq -r '.[] | select(.Name=="private-k8s_subnet") | .ID')
    export FLOATING_NETWORK_ID=$(openstack network list --external -f json |  jq -r ".[] | select(.Name==\"$PUB_NETWORK\") | .ID")
    export ROUTER_ID=$(openstack router list --project $PROJECT_NAME -f json | jq -r ".[] | select(.Name==\"$PUB_NETWORK\") | .ID")

    openstack flavor create --vcpus 2 --ram 4096 --disk 200 --public appfw.medium 2>/dev/null || true
    openstack flavor create --vcpus 4 --ram 8192 --disk 200 --public appfw.large 2>/dev/null || true

    local rancher_file="/root/.rancher/cli2.json"
    cp -f ${rancher_file} ${rancher_file}.bak &&  jq '.Servers.rancherDefault.project = ""' ${rancher_file}.bak > ${rancher_file}
    if ! sudo /usr/local/bin/rancher cluster ls 2>/dev/null | grep $PROJECT_NAME
    then
        echo "Installing app-framework cluster"
        $APPFW_PTH/bin/rancher_client.py create_cluster
    fi

    app_framework_deploy $LOADBALANCER_IP
}

# app_deploy()
# {
#     local ACTION=$1
#     local APP_PIGZ=$2
#     if [ ! -f "$APP_PIGZ" ]; then
#         echo "usage: $0 ${FUNCNAME[0]} install|uninstall /mnt/cephfs/update/app-1.2.3.pigz"
#         exit 1
#     fi

#     if is_running docker ; then
#         [ -e /etc/docker/daemon.json.orig ] || cp -f /etc/docker/daemon.json /etc/docker/daemon.json.orig
#     elif [ -e /etc/docker/daemon.json.orig ] ; then
#         cp -f /etc/docker/daemon.json.orig /etc/docker/daemon.json
#         systemctl restart docker
#     else
#       killall -9 dockerd
#         systemctl stop docker
#         systemctl start docker
#     fi

#     local WORK_DIR=${APP_PIGZ%.pigz}
#     mkdir -p $WORK_DIR
#     tar -I pigz -xf $APP_PIGZ -C $WORK_DIR

#     pushd $WORK_DIR
#     case $ACTION in
#         install) bash deploy.sh install >/dev/null 2>&1 || true ;;
#         uninstall) bash deploy.sh uninstall >/dev/null 2>&1 || true ;;
#         *) echo "Unknown action: $ACTION" ;;
#     esac
#     popd

#     rm -rf $WORK_DIR
# }

app_import()
{
    local APP_PIGZ=$1
    local SKIP_FLAG=$2
    if [ ! -f "$APP_PIGZ" ]; then
        echo "usage: $0 ${FUNCNAME[0]} /mnt/cephfs/update/app-1.2.3.pigz [skip_flavor]"
        exit 1
    fi

    local TMPDIR=$(mktemp -d -t $(basename $APP_PIGZ).XXXXXXXX)
    tar -I pigz -xf $APP_PIGZ -C $TMPDIR

    (cd $TMPDIR && ./import.sh $SKIP_FLAG) || true

    rm -rf $TMPDIR
}

# params:
# $1: project_name
# $2: mgmt_network
# $3: pub_network
app_project_create()
{
    export PROJECT_NAME=$1
    export MGMT_NETWORK=${2:-public}
    export PUB_NETWORK=${3:-public}
    export PROJECT_PASSWORD=$(echo -n $PROJECT_NAME | openssl dgst -sha1 -hmac cube2022 | awk '{print $2}')
    export RANCHER_TOKEN=$(/usr/local/bin/terraform-cube.sh state pull | jq -r '.resources[] | select(.type == "rancher2_bootstrap").instances[0].attributes.token')
    local APPFW_PTH=/opt/appfw

    sudo hex_sdk os_create_project $PROJECT_NAME $MGMT_NETWORK $PUB_NETWORK
    export SUBNET_ID=$(openstack subnet list --project $PROJECT_NAME -f json |  jq -r '.[] | select(.Name=="private-k8s_subnet") | .ID')
    export FLOATING_NETWORK_ID=$(openstack network list --external -f json |  jq -r ".[] | select(.Name==\"$PUB_NETWORK\") | .ID")
    export ROUTER_ID=$(openstack router list --project $PROJECT_NAME -f json | jq -r ".[] | select(.Name==\"$PUB_NETWORK\") | .ID")

    $APPFW_PTH/bin/rancher_client.py create_templates
}

app_project_delete()
{
    export PROJECT_NAME=$1
    export RANCHER_TOKEN=$(/usr/local/bin/terraform-cube.sh state pull | jq -r '.resources[] | select(.type == "rancher2_bootstrap").instances[0].attributes.token')
    local APPFW_PTH=/opt/appfw

    # FIXME: delete all clusters in the project
    $APPFW_PTH/bin/rancher_client.py delete_cluster || true

    $APPFW_PTH/bin/rancher_client.py delete_templates || true
    os_purge_project -y $PROJECT_NAME || true
    openstack -v user delete $PROJECT_NAME >/dev/null 2>&1 || true
}
