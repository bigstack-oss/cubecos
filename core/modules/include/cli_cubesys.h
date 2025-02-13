// CUBE SDK

#ifndef CLI_CUBESYS_H
#define CLI_CUBESYS_H

#include <hex/parse.h>
#include <hex/cli_util.h>
#include <arpa/inet.h>
#include "role_cubesys.h"

/**
 * All the user visible strings
 */
static const char* LABEL_CONFIG_ROLE = "Select a role: ";
static const char* LABEL_CONFIG_DOMAIN = "Specify domain (\"" DOMAIN_DEF "\"): ";
static const char* LABEL_CONFIG_REGION = "Specify region (\"" REGION_DEF "\"): ";
static const char* LABEL_CONFIG_CONTROLLER = "Specify controller hostname: ";
static const char* LABEL_CONFIG_CONTROLLERIP = "Specify controller IP: ";
static const char* LABEL_CONFIG_EXTERNAL = "Specify external IP/domain [optional]: ";
static const char* LABEL_CONFIG_MGMT_IF = "Specify management interface: ";
static const char* LABEL_CONFIG_PROVIDER_IF = "Specify provider interface: ";
static const char* LABEL_CONFIG_PROVIDER_IF_OPT = "Specify provider interface [optional]: ";
static const char* LABEL_CONFIG_OVERLAY_IF = "Specify overlay interface: ";
static const char* LABEL_CONFIG_STORAGE_IF = "Specify storage interface [frontend(,backend)]: ";
static const char* LABEL_CONFIG_SECRET_SEED = "Specify cluster secret seed: ";
static const char* LABEL_CONFIG_MGMT_CIDR = "Specify management CIDR (\"" MGMT_CIDR_DEF "\"): ";

/**
 * A class to handle the cube role change functionality.
 */
class CliCubeSysChanger
{
public:
    CliCubeSysChanger()
    {
        createRoleList();
    }

    ~CliCubeSysChanger() {}

    // Run the role change operation.
    bool configure(CubeSysConfig &config)
    {
        CliPrintf(LABEL_CONFIG_ROLE);

        int idx = CliReadListIndex(m_roles);
        if (idx < 0 || (unsigned int) idx >= m_roles.size()) {
            return false;
        }

        config.role = m_roles[idx];
        int roleId = getCubeRole(idx);
        if (ControlReq(roleId)) {
            if(!setController(config)) {
                return false;
            }
        }

        if (IsControl(roleId) || IsCompute(roleId)) {
            if(!setExternal(config)) {
                return false;
            }
        }

        if(!setMgmt(config)) {
            return false;
        }

        if (IsCompute(roleId)) {
            if(!setProvider(config)) {
                return false;
            }
        }

        if (IsCompute(roleId)) {
            if(!setOverlay(config)) {
                return false;
            }
        }

        if (IsControl(roleId) || IsCompute(roleId) || IsStorage(roleId)) {
            if(!setStorage(config)) {
                return false;
            }
        }

#if 0
        if(!setDomain(config)) {
            return false;
        }
#endif

        if(!setRegion(config)) {
            return false;
        }

        if(!setSecretSeed(config)) {
            return false;
        }

        if (IsControl(roleId)) {
            if(!setMgmtCidr(config)) {
                return false;
            }
        }

        return true;
    }

private:

    // role used by the builder
    CliList m_roles;

    void createRoleList(void)
    {
        m_roles.push_back("control");
        m_roles.push_back("compute");
        m_roles.push_back("storage");
        m_roles.push_back("control-converged");
        m_roles.push_back("edge-core");
        m_roles.push_back("moderator");
    }

    int getCubeRole(int idx)
    {
        static int role[] = { ROLE_CONTROL, ROLE_COMPUTE, ROLE_STORAGE,
            ROLE_CONTROL_CONVERGED, ROLE_CORE, ROLE_MODERATOR };
        return role[idx];
    }

    bool setDomain(CubeSysConfig &config)
    {
        std::string domain;

        if (!CliReadLine(LABEL_CONFIG_DOMAIN, domain)) {
            return false;
        }

        config.domain = domain.length() ? domain : DOMAIN_DEF;
        return true;
    }

    bool setRegion(CubeSysConfig &config)
    {
        std::string region;

        if (!CliReadLine(LABEL_CONFIG_REGION, region)) {
            return false;
        }

        config.region = region.length() ? region : REGION_DEF;
        return true;
    }

    bool setSecretSeed(CubeSysConfig &config)
    {
        std::string seed;

        if (!CliReadLine(LABEL_CONFIG_SECRET_SEED, seed)) {
            return false;
        }

        config.seed = seed;
        return true;
    }

    bool setMgmtCidr(CubeSysConfig &config)
    {
        std::string cidr;

        if (!CliReadLine(LABEL_CONFIG_MGMT_CIDR, cidr)) {
            return false;
        }
        else {
            if (cidr.length()) {
                struct in_addr v4addr;
                std::vector<std::string> comps = hex_string_util::split(cidr, '/');
                if (comps.size() != 2 || !HexParseIP(comps[0].c_str(), AF_INET, &v4addr) ||
                    !(comps[1] == "8" || comps[1] == "16")) {
                    return false;
                }
            }
        }

        config.mgmtCidr = cidr.length() ? cidr : MGMT_CIDR_DEF;

        return true;
    }

    bool setController(CubeSysConfig &config)
    {
        std::string controller;
        std::string controllerIp;

        if (!CliReadLine(LABEL_CONFIG_CONTROLLER, controller) || controller.length() <= 0) {
            return false;
        }

        if (!CliReadLine(LABEL_CONFIG_CONTROLLERIP, controllerIp) || controllerIp.length() <= 0) {
            return false;
        }

        // TODO: verify IP/HOSTNAME/DOMAIN

        config.controller = controller;
        config.controllerIp = controllerIp;
        return true;
    }

    bool setExternal(CubeSysConfig &config)
    {
        std::string external;

        if (!CliReadLine(LABEL_CONFIG_EXTERNAL, external)) {
            return false;
        }

        config.external = external;
        return true;
    }

    bool setMgmt(CubeSysConfig &config)
    {
        std::string mgmt;

        if (!CliReadLine(LABEL_CONFIG_MGMT_IF, mgmt) || mgmt.length() <= 0) {
            return false;
        }

        config.mgmt = mgmt;
        return true;
    }

    bool setProvider(CubeSysConfig &config, bool optional = false)
    {
        std::string provider;

        if (!CliReadLine(optional ? LABEL_CONFIG_PROVIDER_IF_OPT : LABEL_CONFIG_PROVIDER_IF, provider)) {
            return false;
        }

        if (!optional && provider.length() <= 0)
            return false;

        config.provider = provider;
        return true;
    }

    bool setOverlay(CubeSysConfig &config)
    {
        std::string overlay;

        if (!CliReadLine(LABEL_CONFIG_OVERLAY_IF, overlay) || overlay.length() <= 0) {
            return false;
        }

        config.overlay = overlay;
        return true;
    }

    bool setStorage(CubeSysConfig &config)
    {
        std::string storage;

        if (!CliReadLine(LABEL_CONFIG_STORAGE_IF, storage) || storage.length() <= 0) {
            return false;
        }

        config.storage = storage;
        return true;
    }
};

#endif /* endif CLI_CUBESYS_H */

