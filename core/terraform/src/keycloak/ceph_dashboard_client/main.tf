terraform {
  required_version = ">= 0.13"

  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = "= 5.9.0"
    }
  }
}

provider "keycloak" {
  client_id                = "admin-cli"
  username                 = "admin"
  password                 = var.keycloak_admin_password
  url                      = "https://${var.cube_controller}:10443"
  # Keycloak still serves under /auth; the provider defaults base_path to "" since 4.0.
  base_path                = "/auth"
  tls_insecure_skip_verify = true
}

data "keycloak_realm" "master" {
  realm = "master"
}

resource "keycloak_saml_client" "ceph_dashboard_client" {
  realm_id  = data.keycloak_realm.master.id
  client_id = "https://${var.cube_controller}:7443/ceph/auth/saml2/metadata"
  name      = "ceph_dashboard"

  signature_algorithm    = "RSA_SHA256"
  sign_assertions        = true
  # encryption_algorithm is left unset on purpose, as in api_client: Keycloak's default,
  # AES-256-GCM, which the dashboard's python3-saml decrypts, replaces the AES-128-CBC pin
  # Keycloak 26 put on clients that predate it.
  encrypt_assertions     = true
  front_channel_logout   = true
  name_id_format         = "persistent"
  signing_certificate    = file("/var/www/certs/server.cert")
  encryption_certificate = file("/var/www/certs/server.cert")

  valid_redirect_uris                 = ["https://${var.cube_controller}:7443/ceph/auth/saml2"]
  assertion_consumer_post_url         = "https://${var.cube_controller}:7443/ceph/auth/saml2"
  logout_service_redirect_binding_url = "https://${var.cube_controller}:7443/ceph/auth/saml2/logout"
}

resource "keycloak_saml_user_property_protocol_mapper" "ceph_dashboard_username_mapper" {
  realm_id  = data.keycloak_realm.master.id
  client_id = keycloak_saml_client.ceph_dashboard_client.id
  name      = "username"

  user_property              = "username"
  saml_attribute_name        = "username"
  saml_attribute_name_format = "Basic"
}

resource "keycloak_saml_client_default_scopes" "ceph_dashboard_client_default_scopes" {
  realm_id  = data.keycloak_realm.master.id
  client_id = keycloak_saml_client.ceph_dashboard_client.id

  # Empty on purpose: this also takes off the AuthnContextClassRef scope that Keycloak 26
  # attaches to every SAML client, the way it already took off role_list.
  default_scopes = []
}
