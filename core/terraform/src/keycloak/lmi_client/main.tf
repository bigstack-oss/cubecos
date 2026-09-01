terraform {
  required_version = ">= 0.13"

  required_providers {
    keycloak = {
      source  = "mrparkers/keycloak"
      version = "= 4.4.0"
    }
  }
}

provider "keycloak" {
  client_id                = "admin-cli"
  username                 = "admin"
  password                 = var.keycloak_admin_password
  url                      = "https://${var.cube_controller}:10443"
  # Keycloak still serves under /auth; provider 4.x defaults base_path to "".
  base_path                = "/auth"
  tls_insecure_skip_verify = true
}

data "keycloak_realm" "master" {
  realm = "master"
}
