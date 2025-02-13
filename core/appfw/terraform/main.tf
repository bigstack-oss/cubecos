terraform {
  backend "kubernetes" {
    secret_suffix    = "appfw-state"
    config_path      = "/etc/rancher/k3s/k3s.yaml"
  }
}

terraform {
  required_providers {
    rancher2 = {
      source = "rancher/rancher2"
      version = "1.22.2"
    }
  }
}

# provider "rancher2" {
#   alias = "bootstrap"

#   api_url   = "https://cube-controller:10443"
#   bootstrap = true
#   insecure = true
# }

# resource "rancher2_bootstrap" "admin" {
#   provider = rancher2.bootstrap

#   password = "admin"
#   telemetry = false
# }

# provider "rancher2" {
#   alias = "admin"

#   api_url = rancher2_bootstrap.admin.url
#   token_key = rancher2_bootstrap.admin.token
#   insecure = true
# }

provider "rancher2" {
  api_url    = "https://cube-controller:10443"
  token_key = var.token_key
  insecure = true
}




resource "rancher2_cluster_template" "appfw" {
  name = "app-framework"
  description = "Cube app-framwork cluster template"
  template_revisions {
    name = "v1"
    cluster_config {
      rke_config {
        kubernetes_version = "v1.20.11-rancher1-1"
        network {
          plugin = "canal"
          mtu = 1342
        }
        # services {
        #   etcd {
        #     backup_config {
        #       enabled = true
        #     }
        #     creation = "12h"
        #     retention = "72h"
        #   }
        # }
        cloud_provider {
          name = "openstack"
          openstack_cloud_provider {
            global {
              auth_url = var.auth_url
              domain_name = "default"
              region = "RegionOne"
              tenant_name = var.tenant_name
              username = var.tenant_name
              password = var.password
            }
            block_storage {
              bs_version = "v2"
              ignore_volume_az = true
              trust_device_path = true
            }
            load_balancer {
              lb_version = "v2"
              subnet_id = var.subnet_id
              floating_network_id = var.floating_network_id
              use_octavia = true
            }
            route {
              router_id = var.router_id
            }
          }
        }
      }
    }
    default = true
  }
}

resource "rancher2_cluster" "appfw" {
  name = "app-framework"
  description = "Cube app-framwork cluster"
  cluster_template_id = rancher2_cluster_template.appfw.id
  cluster_template_revision_id = rancher2_cluster_template.appfw.template_revisions.0.id

  # depends_on = [data.rancher2_node_template.appfw]
}

# data "rancher2_node_template" "appfw" {
#   name = "app-framework"
# }

# resource "rancher2_node_pool" "appfw_master" {
#   name = "app-framework-master"
#   hostname_prefix =  "app-framework-master-"
#   cluster_id =  rancher2_cluster.appfw.id
#   node_template_id = data.rancher2_node_template.appfw.id
#   quantity = 1
#   control_plane = true
#   etcd = true
#   worker = false
# }

# resource "rancher2_node_pool" "appfw_worker" {
#   name = "app-framework-worker"
#   hostname_prefix =  "app-framework-worker-"
#   cluster_id =  rancher2_cluster.appfw.id
#   node_template_id = data.rancher2_node_template.appfw.id
#   quantity = 1
#   control_plane = false
#   etcd = false
#   worker = true
# }
