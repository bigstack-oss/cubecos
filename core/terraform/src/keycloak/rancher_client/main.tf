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

resource "keycloak_saml_client" "rancher_client" {
  realm_id                = data.keycloak_realm.master.id
  client_id               = "https://${var.cube_controller}:10443/v1-saml/keycloak/saml/metadata"
  name                    = "rancher"

  signature_algorithm     = "RSA_SHA256"
  sign_documents          = true
  sign_assertions         = true
  include_authn_statement = false
  client_signature_required = false
  force_post_binding = false

  valid_redirect_uris = ["https://${var.cube_controller}:10443/v1-saml/keycloak/saml/acs"]
}

resource "keycloak_saml_user_property_protocol_mapper" "rancher_user_property_mapper" {
  realm_id                   = data.keycloak_realm.master.id
  client_id                  = keycloak_saml_client.rancher_client.id
  name                       = "username"

  user_property              = "username"
  saml_attribute_name        = "uid"
  saml_attribute_name_format = "Basic"
}

resource "keycloak_generic_client_protocol_mapper" "rancher_group_list" {
  realm_id        = data.keycloak_realm.master.id
  client_id       = keycloak_saml_client.rancher_client.id
  name            = "groups"                   # Name
  protocol        = "saml"                         # Protocol
  protocol_mapper = "saml-group-membership-mapper" # Mapper Type
  config = {
    "attribute.name"       = "member"
    "single"               = "true"
    "full.path"            = "false"
    "attribute.nameformat" = "Basic"
  }
}
