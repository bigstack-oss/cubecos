#!/usr/bin/env python3

import os
import sys
import time
import requests
import urllib3
import re

import rancher

urllib3.disable_warnings()

token = os.environ.get('RANCHER_TOKEN')
project_name = os.environ.get('PROJECT_NAME')
project_password = os.environ.get('PROJECT_PASSWORD')
os_auth_url = os.environ.get('OS_AUTH_URL')
subnet_id = os.environ.get('SUBNET_ID')
floating_network_id = os.environ.get('FLOATING_NETWORK_ID')
router_id = os.environ.get('ROUTER_ID')
public_network = os.environ.get('PUB_NETWORK')
management_network = os.environ.get('MGMT_NETWORK')
cube_controller = os.environ.get('CUBE_CONTROLLER')

client = rancher.Client(url='https://cube-controller:10443/v3', token=token, verify=False)

def create_templates():
    # storage_class_yaml = "---\napiVersion: storage.k8s.io/v1\nkind: StorageClass\nmetadata:\n  annotations:\n    storageclass.beta.kubernetes.io/is-default-class: \"true\"\n    storageclass.kubernetes.io/is-default-class: \"true\"\n  name: cinder\nprovisioner: kubernetes.io/cinder\nreclaimPolicy: Delete\nvolumeBindingMode: Immediate\nallowVolumeExpansion: true\n"
    # ingress_lb_yaml = "---\napiVersion: v1\nkind: Service\nmetadata:\n  name: ingress-lb\n  namespace: ingress-nginx\nspec:\n  ports:\n  - name: https\n    port: 443\n    protocol: TCP\n    targetPort: 443\n  selector:\n    app: ingress-nginx \n  type: LoadBalancer\n"

    addons = ""
    # if project_name == "app-framework":
    #     addons += ingress_lb_yaml

    clusterTemplate = client.create_cluster_template(name=project_name)
    clusterTemplateRevision = client.create_cluster_template_revision(name='v1', clusterTemplateId=clusterTemplate.id,
        clusterConfig={
            # "enableClusterMonitoring": True,
            "rancherKubernetesEngineConfig": {
                "kubernetesVersion": "1.26.x",
                "network": {
                    "mtu": 1392,
                },
                "ingress": {
                    "defaultBackend": False,
                },
                "services": {
                    "kubeController": {
                        "extraArgs": {
                            "cluster-signing-cert-file": "/etc/kubernetes/ssl/kube-ca.pem",
                            "cluster-signing-key-file": "/etc/kubernetes/ssl/kube-ca-key.pem",
                        },
                    },
                    # "etcd" :{
                    #     "extraArgs": {
                    #         "election-timeout": 5000,
                    #         "heartbeat-interval": 500,
                    #     }
                    # },
                },
                "addons": addons,
            },
            "localClusterAuthEndpoint": {
                "enabled": True,
            },
        },
        questions=[
            {
                "default": "v1.26.8-rancher1-1",
                "required": False,
                "type": "string",
                "variable": "rancherKubernetesEngineConfig.kubernetesVersion",
            }
        ],
    )

    if project_name == "app-framework":
        nodeTemplate_master = create_nodeTemplate(project_name + ":appfw.medium", "appfw.medium")
        nodeTemplate_worker = create_nodeTemplate(project_name + ":appfw.large", "appfw.large")

        return clusterTemplate.id, clusterTemplateRevision.id, nodeTemplate_master.id, nodeTemplate_worker.id
    else:
        flavorSizes = ["small", "medium", "large"]
        for s in flavorSizes:
            create_nodeTemplate(project_name+":basic."+s, "basic."+s)

def create_nodeTemplate(name, flavor):
    template = client.create_nodeTemplate(
        name=name,
        description=project_name,
        driver='cube',
        cubeConfig={
            "00_username": project_name,
            "01_password": project_password,
            "02_tenantName": project_name,
            "domainName": "default",
            "flavorName": flavor,
            "floatingipPool": management_network,
            "imageName": "rancher-cluster-image",
            "netName": "private-k8s",
            "secGroups": "default,default-k8s",
            "sshUser": "ubuntu"
        },
        logOpt={
            "max-file": "3",
            "max-size": "10m",
        },
        engineInsecureRegistry=["localhost:30000", f"{cube_controller}:5080"],
        engineRegistryMirror=["http://localhost:30000", f"http://{cube_controller}:5080"]
    )

    return template

def delete_templates():
    for n in client.list_nodeTemplate(driver='cube').data:
        # Wait node pool to be deleted before deleting node template
        if re.match(project_name + ":.*", n.name):
            print("Deleting nodeTemplate: %s" % n.name )
            for i in range(10):
                result = client.list_nodePool(nodeTemplateId=n.id).data
                time.sleep(5)
                if len(result) > 0:
                    print("Resource: %s, State: %s" % (result[0].name, result[0].state) )
                else:
                    client.delete(n)
                    break

    for n in client.list_clusterTemplate(name=project_name).data:
        client.delete(n)

def create_cluster():
    clusterTemplate_id, clusterTemplateRevision_id, nodeTemplate_master_id, nodeTemplate_worker_id = create_templates()

    appfw = client.create_cluster(name=project_name, clusterTemplateId=clusterTemplate_id, clusterTemplateRevisionId=clusterTemplateRevision_id,
        # answers={
        #     "values": {
        #       "rancherKubernetesEngineConfig.kubernetesVersion": "",
        #     },
        # },
    )

    time.sleep(5)
    client.create_node_pool(name=project_name + '-master', hostnamePrefix=project_name + '-master-', nodeTemplateId=nodeTemplate_master_id,
        clusterId=appfw.id, drainBeforeDelete=True, controlPlane=True, etcd=True, worker=False)
    client.create_node_pool(name=project_name + '-worker', hostnamePrefix=project_name + '-worker-', nodeTemplateId=nodeTemplate_worker_id,
        clusterId=appfw.id, drainBeforeDelete=True, controlPlane=False, etcd=False, worker=True)

    # timeout = 1500
    # start = time.time()

    # state = ""
    # while state != 'active':
    #     time.sleep(30)
    #     elapsed = time.time() - start
    #     if  elapsed > timeout:
    #         msg = 'Timeout waiting for [{}:{}] to be done after {} seconds'
    #         msg = msg.format(appfw.type, appfw.id, elapsed)
    #         raise Exception(msg)

    #     state = client.by_id_cluster(appfw.id).state
    #     print(f'Waiting for resource: {appfw.type}, name: {appfw.name}, state: {appfw.state}, time elapsed: {elapsed} secs')

def delete_cluster():
    for c in client.list_cluster(name=project_name).data:
        client.delete(c)
        print(f'Waiting for deleting cluster: {c.name}')
        try:
            client.wait_success(c)
        except Exception:
            pass


if sys.argv[1] == "create_cluster":
    create_cluster()
elif sys.argv[1] == "delete_cluster":
    delete_cluster()
elif sys.argv[1] == "create_templates":
    create_templates()
elif sys.argv[1] == "delete_templates":
    delete_templates()
