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

resource "keycloak_saml_client" "keystone_client" {
  realm_id                = data.keycloak_realm.master.id
  client_id               = "https://${var.cube_controller}:5443/v3/mellon/metadata"
  name                    = "keystone"

  signature_algorithm     = "RSA_SHA256"
  sign_assertions         = true
  front_channel_logout    = true
  encrypt_assertions      = false
  client_signature_required = false
  name_id_format          = "transient"
  signing_certificate     = file("/etc/httpd/federation/v3.cert")
  encryption_certificate  = file("/etc/httpd/federation/v3.cert")

  valid_redirect_uris = ["https://${var.cube_controller}:5443/v3/mellon/postResponse", "https://${var.cube_controller}:5443/v3/mellon/artifactResponse", "https://${var.cube_controller}:5443/v3/mellon/paosResponse"]
  assertion_consumer_post_url = "https://${var.cube_controller}:5443/v3/mellon/postResponse"
  logout_service_redirect_binding_url = "https://${var.cube_controller}:5443/v3/mellon/logout"
}

resource "keycloak_saml_user_property_protocol_mapper" "keystone_username_mapper" {
  realm_id                   = data.keycloak_realm.master.id
  client_id                  = keycloak_saml_client.keystone_client.id
  name                       = "username"

  user_property              = "username"
  saml_attribute_name        = "username"
  saml_attribute_name_format = "Basic"
}

resource "keycloak_generic_client_protocol_mapper" "keystone_groups_mapper" {
  realm_id        = data.keycloak_realm.master.id
  client_id       = keycloak_saml_client.keystone_client.id
  name            = "groups"                   # Name
  protocol        = "saml"                         # Protocol
  protocol_mapper = "saml-group-membership-mapper" # Mapper Type
  config = {
    "attribute.name"       = "groups"
    "single"               = "true"
    "full.path"            = "false"
    "attribute.nameformat" = "Basic"
  }
}
