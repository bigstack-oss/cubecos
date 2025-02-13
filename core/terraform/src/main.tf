terraform {
  backend "etcdv3" {
    endpoints = ["127.0.0.1:12379"]
    lock      = true
    prefix    = "terraform-state/"
  }
}

module "mysql" {
  source = "./mysql/"

  mysql_dbname = var.mysql_dbname
}


module "keycloak" {
  source = "./keycloak/"

  #cube_controller = var.cube_controller
}

module "keycloak_lmi" {
  source = "./keycloak/lmi_client/"

  cube_controller = var.cube_controller
}

module "keycloak_keystone" {
  source = "./keycloak/keystone_client/"

  cube_controller = var.cube_controller
}

module "keycloak_rancher" {
  source = "./keycloak/rancher_client/"

  cube_controller = var.cube_controller
}

module "keycloak_ceph_dashboard" {
  source = "./keycloak/ceph_dashboard_client/"

  cube_controller = var.cube_controller
}

module "rancher" {
  source = "./rancher/"

  cube_controller = var.cube_controller
}

output "rancher" {
    value = module.rancher
}
