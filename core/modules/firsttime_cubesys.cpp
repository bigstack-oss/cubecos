// HEX SDK

#include <cstring>
#include <cstdlib>

#include <hex/cli_util.h>
#include <hex/yml_util.h>
#include <hex/string_util.h>

#include <hex/firsttime_module.h>
#include <hex/firsttime_impl.h>

#include "include/cli_cubesys.h"
#include "include/policy_cubesys.h"

using namespace hex_firsttime;

/**
 * All the user visible strings
 */
static const char* LABEL_ROLE_TITLE = "CubeCOS Role";
static const char* LABEL_ROLE_CURRENT = "Current role: %s";
static const char* LABEL_CONTROLLER_CURRENT = "Current Controller: %s(%s)";
static const char* LABEL_EXTERNAL_CURRENT = "Current External IP/Domain: %s";
static const char* LABEL_MGMT_CURRENT = "Current Management: %s";
static const char* LABEL_PROVIDER_CURRENT = "Current Provider: %s";
static const char* LABEL_OVERLAY_CURRENT = "Current Overlay: %s";
static const char* LABEL_STORAGE_CURRENT = "Current Storage: %s";
static const char* LABEL_DOMAIN_REGION_CURRENT = "Current Domain/Region: %s/%s";
//static const char* LABEL_COMPUTE_MAP_CURRENT = "Current Compute Node Map: %s(%s[%lu])";
static const char* LABEL_SECRET_SEED_CURRENT = "Current CubeCOS Secret Seed: %s";
static const char* LABEL_MGMT_CIDR_CURRENT = "Current Management CIDR: %s";
static const char* LABEL_ROLE_CHANGE_MENU    = "Change role";
static const char* LABEL_ROLE_CHANGE_HEADING = "Change Role";
static const char* LABEL_ROLE = "Role: %s";
static const char* LABEL_CONTROLLER = "Controller: %s(%s)";
static const char* LABEL_EXTERNAL = "External IP/Domain: %s";
static const char* LABEL_MGMT = "Management: %s";
static const char* LABEL_PROVIDER = "Provider: %s";
static const char* LABEL_OVERLAY = "Overlay: %s";
static const char* LABEL_STORAGE = "Storage: %s";
static const char* LABEL_DOMAIN_REGION = "Domain/Region: %s/%s";
//static const char* LABEL_COMPUTE_MAP = "Compute Node Map: %s(%s[%lu])";
static const char* LABEL_SECRET_SEED = "CubeCOS Secret Seed: %s";
static const char* LABEL_MGMT_CIDR = "Management CIDR: %s";

class CubeSysModule : public MenuModule {
public:
    CubeSysModule(int order)
     : MenuModule(order, LABEL_ROLE_TITLE)
    {
        addOption(LABEL_ROLE_CHANGE_MENU, LABEL_ROLE_CHANGE_HEADING);
    }

    ~CubeSysModule() { }

    void summary()
    {
        if (!PolicyManager()->load(m_policy)) {
            CliPrintf("Error retrieving cube system settings");
        }

        std::string role = m_policy.getRole();
        int roleId = GetCubeRole(role);

        CliPrintf(LABEL_ROLE, role.c_str());
        if(ControlReq(roleId)) {
            CliPrintf(LABEL_CONTROLLER, m_policy.getController(), m_policy.getControllerIp());
        }

        if(IsControl(roleId) || IsCompute(roleId)) {
            CliPrintf(LABEL_EXTERNAL, m_policy.getExternal());
        }

        CliPrintf(LABEL_MGMT, m_policy.getMgmt());

        if(IsCompute(roleId)) {
            CliPrintf(LABEL_PROVIDER, m_policy.getProvider());
            CliPrintf(LABEL_OVERLAY, m_policy.getOverlay());
        }
        if(IsControl(roleId) || IsCompute(roleId) || IsStorage(roleId)) {
            CliPrintf(LABEL_STORAGE, m_policy.getStorage());
        }
        CliPrintf(LABEL_DOMAIN_REGION, m_policy.getDomain(), m_policy.getRegion());
        //CliPrintf(LABEL_COMPUTE_MAP,
        //          m_policy.getComputePrefix(), m_policy.getComputeStart(), m_policy.getComputeNumber());
        CliPrintf(LABEL_SECRET_SEED, m_policy.getSecretSeed());

        if(IsControl(roleId)) {
            CliPrintf(LABEL_MGMT_CIDR, m_policy.getMgmtCidr());
        }
    }

protected:

    bool loopSetup()
    {
        return PolicyManager()->load(m_policy, true);
    }

    virtual void printLoopHeader()
    {
        std::string role = m_policy.getRole();
        int roleId = GetCubeRole(role);
        CliPrintf(LABEL_ROLE_CURRENT, role.c_str());
        if(ControlReq(roleId)) {
            CliPrintf(LABEL_CONTROLLER_CURRENT, m_policy.getController(), m_policy.getControllerIp());
        }

        if(IsControl(roleId) || IsCompute(roleId)) {
            CliPrintf(LABEL_EXTERNAL_CURRENT, m_policy.getExternal());
        }

        CliPrintf(LABEL_MGMT_CURRENT, m_policy.getMgmt());

        if(IsCompute(roleId)) {
            CliPrintf(LABEL_PROVIDER_CURRENT, m_policy.getProvider());
            CliPrintf(LABEL_OVERLAY_CURRENT, m_policy.getOverlay());
        }
        if(IsControl(roleId) || IsCompute(roleId) || IsStorage(roleId)) {
            CliPrintf(LABEL_STORAGE_CURRENT, m_policy.getStorage());
        }
        CliPrintf(LABEL_DOMAIN_REGION_CURRENT, m_policy.getDomain(), m_policy.getRegion());
        //CliPrintf(LABEL_COMPUTE_MAP_CURRENT,
        //          m_policy.getComputePrefix(), m_policy.getComputeStart(), m_policy.getComputeNumber());
        CliPrintf(LABEL_SECRET_SEED_CURRENT, m_policy.getSecretSeed());

        if(IsControl(roleId)) {
            CliPrintf(LABEL_MGMT_CIDR_CURRENT, m_policy.getMgmtCidr());
        }
    }

    virtual bool doAction(int index)
    {
        CubeSysConfig config;
        m_policy.getConfig(&config);

        switch(index)
        {
            case 0:
                // Invoke the role menu item builder
                if (m_cubesysChanger.configure(config)) {
                    if (!m_policy.setConfig(config))
                        return false;

                    if (!PolicyManager()->save(m_policy))
                        return false;
                }
                break;
            default:
                return false;
        }
        return true;
    }

private:
    // The role menu item builders
    CliCubeSysChanger m_cubesysChanger;

    // The time policy to be loaded, modified and saved
    CubeSysPolicy m_policy;
};

FIRSTTIME_MODULE(CubeSysModule, FT_ORDER_LAST + 2);

