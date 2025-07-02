terraform {
  required_providers {
    rancher2 = {
      source = "rancher/rancher2"
      version = "7.0.0"
    }
  }
}

provider "rancher2" {
  alias = "bootstrap"

  api_url   = "https://${var.cube_controller}:10443"
  bootstrap = true
  insecure = true
}

resource "rancher2_bootstrap" "admin" {
  provider = rancher2.bootstrap

  initial_password = "default-admin"
  password = "default-admin"
}

provider "rancher2" {
  alias = "admin"

  api_url = rancher2_bootstrap.admin.url
  token_key = rancher2_bootstrap.admin.token
  insecure = true
}

resource "rancher2_auth_config_keycloak" "keycloak" {
  provider = rancher2.admin

  display_name_field = "uid"
  uid_field = "uid"
  user_name_field = "uid"
  groups_field = "member"
  rancher_api_host = "https://${var.cube_controller}:10443"
  sp_cert = file("/var/www/certs/server.cert")
  sp_key = file("/var/www/certs/server.key")
  idp_metadata_content = file("/etc/keycloak/saml-metadata.xml")
  #idp_metadata_content = var.idp_metadata_content
  access_mode           = "required"
  allowed_principal_ids = [
    #"keycloak_user://admin",
    "keycloak_group://cube-admins",
    "keycloak_group://cube-users",
  ]
}

resource "rancher2_global_role_binding" "cube_admins" {
  provider = rancher2.admin

  global_role_id = "admin"
  group_principal_id = "keycloak_group://cube-admins"
}

resource "rancher2_global_role_binding" "cube_users" {
  provider = rancher2.admin

  global_role_id = "user"
  group_principal_id = "keycloak_group://cube-users"
}
