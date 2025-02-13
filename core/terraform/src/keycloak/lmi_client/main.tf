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

resource "keycloak_saml_client" "lmi_client" {
  realm_id                = data.keycloak_realm.master.id
  client_id               = "https://${var.cube_controller}/v1/auth/metadata"
  name                    = "lmi"

  signature_algorithm     = "RSA_SHA256"
  sign_assertions         = true
  encrypt_assertions      = true
  front_channel_logout    = true
  name_id_format          = "persistent"
  signing_certificate     = file("/var/www/certs/server.cert")
  encryption_certificate  = file("/var/www/certs/server.cert")

  valid_redirect_uris = ["https://${var.cube_controller}/v1/auth/consume"]
  assertion_consumer_post_url = "https://${var.cube_controller}/v1/auth/consume"
}

resource "keycloak_saml_user_property_protocol_mapper" "lmi_username_mapper" {
  realm_id                   = data.keycloak_realm.master.id
  client_id                  = keycloak_saml_client.lmi_client.id
  name                       = "username"

  user_property              = "username"
  saml_attribute_name        = "username"
  saml_attribute_name_format = "Basic"
}

resource "keycloak_generic_client_protocol_mapper" "lmi_groups_mapper" {
  realm_id        = data.keycloak_realm.master.id
  client_id       = keycloak_saml_client.lmi_client.id
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
