terraform {
  required_version = ">= 0.13"

  required_providers {
    keycloak = {
      source = "mrparkers/keycloak"
      version = "= 3.10.0"
    }
  }
}

provider "keycloak" {
  client_id     = "admin-cli"
  username      = "admin"
  password      = "admin"
  url           = "https://${var.cube_controller}:10443"
  tls_insecure_skip_verify = true
}

data "keycloak_realm" "master" {
    realm   = "master"
}

resource "keycloak_saml_client" "ceph_dashboard_client" {
  realm_id                = data.keycloak_realm.master.id
  client_id               = "https://${var.cube_controller}:7443/ceph/auth/saml2/metadata"
  name                    = "ceph_dashboard"

  signature_algorithm     = "RSA_SHA256"
  sign_assertions         = true
  encrypt_assertions      = true
  front_channel_logout    = true
  name_id_format          = "persistent"
  signing_certificate     = file("/var/www/certs/server.cert")
  encryption_certificate  = file("/var/www/certs/server.cert")

  valid_redirect_uris = ["https://${var.cube_controller}:7443/ceph/auth/saml2"]
  assertion_consumer_post_url = "https://${var.cube_controller}:7443/ceph/auth/saml2"
  logout_service_redirect_binding_url = "https://${var.cube_controller}:7443/ceph/auth/saml2/logout"
}

resource "keycloak_saml_user_property_protocol_mapper" "ceph_dashboard_username_mapper" {
  realm_id                   = data.keycloak_realm.master.id
  client_id                  = keycloak_saml_client.ceph_dashboard_client.id
  name                       = "username"

  user_property              = "username"
  saml_attribute_name        = "username"
  saml_attribute_name_format = "Basic"
}

resource "keycloak_saml_client_default_scopes" "ceph_dashboard_client_default_scopes" {
  realm_id  = data.keycloak_realm.master.id
  client_id = keycloak_saml_client.ceph_dashboard_client.id

  default_scopes = []
}