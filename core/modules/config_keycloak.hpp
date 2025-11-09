// CUBE SDK

#ifndef CUBE_CONFIG_KEYCLOAK_H
#define CUBE_CONFIG_KEYCLOAK_H

#include "include/role_cubesys.h"

#include <helm.hpp>
#include <hex/config_global.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/dryrun.h>
#include <hex/log.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <k3s.hpp>
#include <terraform.hpp>

#include <unistd.h>

#define KEYCLOAK_SAML_METADATA_FILE "/etc/keycloak/saml-metadata.xml"
#define KEYCLOAK_SAML_METADATA_FILE_TMP "/tmp/keycloak-saml-metadata.xml"

#endif /* endif CUBE_CONFIG_KEYCLOAK_H */
