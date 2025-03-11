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
  url           = "https://cube-controller:10443"
  tls_insecure_skip_verify = true
}

data "keycloak_realm" "master" {
    realm   = "master"
}

resource "keycloak_group" "cube_admins" {
  realm_id = data.keycloak_realm.master.id
  name     = "cube-admins"
}

resource "keycloak_group" "cube_users" {
  realm_id = data.keycloak_realm.master.id
  name     = "cube-users"
}

resource "keycloak_group" "ops_domain_default" {
  realm_id = data.keycloak_realm.master.id
  name     = "ops-domain:default"
}

resource "keycloak_default_groups" "default" {
  realm_id  = data.keycloak_realm.master.id

  group_ids = [
    keycloak_group.cube_users.id
  ]

  depends_on = [
    keycloak_group.cube_users
  ]
}


# resource "keycloak_user" "cube_admin" {
#   realm_id = data.keycloak_realm.master.id
#   username = "cube-admin"
#   enabled  = true

# #   email          = var.root_email
# #   first_name     = var.root_firstname
# #   last_name      = var.root_lastname
# #   email_verified = true

#   attributes = {
#   }

#   initial_password {
#     value     = "admin"
#   }
# }

# realm role "admin"
data "keycloak_role" "realm_admin" {
  realm_id = data.keycloak_realm.master.id
  name     = "admin"
}

# account client
data "keycloak_openid_client" "account" {
  realm_id  = data.keycloak_realm.master.id
  client_id = "account"
}

# account client role "manage-account"
data "keycloak_role" "account_manage_account" {
  realm_id = data.keycloak_realm.master.id
  client_id = data.keycloak_openid_client.account.id
  name     = "manage-account"
}

# account client role "view-profile"
data "keycloak_role" "account_view_profile" {
  realm_id = data.keycloak_realm.master.id
  client_id = data.keycloak_openid_client.account.id
  name     = "view-profile"
}

# add roles for cube-admins group
resource "keycloak_group_roles" "cube_admins_roles" {
  realm_id = data.keycloak_realm.master.id
  group_id = keycloak_group.cube_admins.id

  exhaustive = false
  role_ids = [
    data.keycloak_role.realm_admin.id,
    data.keycloak_role.account_manage_account.id,
    data.keycloak_role.account_view_profile.id,
  ]
}

# members in cube-admins group
resource "keycloak_group_memberships" "group_admins" {
  realm_id = data.keycloak_realm.master.id
  group_id = keycloak_group.cube_admins.id

  members  = [
    "admin"
  ]

  lifecycle {
    ignore_changes = [members]
  }

  # depends_on = [
  #   keycloak_user.cube_admin
  # ]
}


# resource "null_resource" "saml_idp_descriptor" {
#   triggers = {
#     always_run = "${timestamp()}"
#   }

#   provisioner "local-exec" {
#     command = "curl -k https://${var.cube_controller}:10443/auth/realms/master/protocol/saml/descriptor | xmllint --format - | sed -e '1d' -e '/EntitiesDescriptor/d' > saml-metadata.xml"
#   }
# }

# data "local_file" "saml_idp_descriptor" {
#   filename = "saml-metadata.xml"
#   depends_on = [null_resource.saml_idp_descriptor]
# }

# output "saml_idp_descriptor" {
#   value = data.local_file.saml_idp_descriptor.content
# }
