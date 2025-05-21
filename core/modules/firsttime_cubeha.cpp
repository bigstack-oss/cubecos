// HEX SDK

#include <cstring>
#include <cstdlib>

#include <hex/cli_util.h>
#include <hex/yml_util.h>

#include <hex/firsttime_module.h>
#include <hex/firsttime_impl.h>

#include "include/cli_cubeha.h"
#include "include/policy_cubesys.h"

using namespace hex_firsttime;

/**
 * All the user visible strings
 */
static const char* LABEL_HA_TITLE = "CubeCOS High Availability";
static const char* LABEL_CURRENT_HA = "Current HA setting: %s";
static const char* LABEL_CURRENT_CONTROL_VIP = "Current Control Virtual IP: %s";
static const char* LABEL_CURRENT_CONTROL_VHN = "Current Control Virtual Hostname: %s";
static const char* LABEL_CURRENT_CONTROL_GROUP = "Current Control Group: %s";
// static const char* LABEL_CURRENT_STORAGE_GROUP = "Current Storage Group: %s";
static const char* LABEL_HA_CHANGE_MENU = "Change HA";
static const char* LABEL_HA_CHANGE_HEADING = "Change HA";
static const char* LABEL_HA = "High Availability: %s";
static const char* LABEL_CONTROL_VIP = "Control Virtual IP: %s";
static const char* LABEL_CONTROL_VHN = "Control Virtual Hostname: %s";
static const char* LABEL_CONTROL_GROUP = "Control Group: %s";
// static const char* LABEL_STORAGE_GROUP = "Storage Group: %s";

class CubeHaModule : public MenuModule {
public:
    CubeHaModule(int order)
     : MenuModule(order, LABEL_HA_TITLE)
    {
        addOption(LABEL_HA_CHANGE_MENU, LABEL_HA_CHANGE_HEADING);
    }

    ~CubeHaModule() { }

    void summary()
    {
        if (!PolicyManager()->load(m_policy)) {
            CliPrintf("Error retrieving cube HA settings");
        }

        CubeSysConfig cfg;

        m_policy.getConfig(&cfg);
        int roleId = GetCubeRole(cfg.role);

        CliPrintf(LABEL_HA, m_policy.getHA());
        if (cfg.ha) {
            if (IsControl(roleId)) {
                CliPrintf(LABEL_CONTROL_VHN, m_policy.getController());
                CliPrintf(LABEL_CONTROL_VIP, m_policy.getControlVip());
                // CliPrintf(LABEL_STORAGE_GROUP, m_policy.getStorageGroup().c_str());
            }
            CliPrintf(LABEL_CONTROL_GROUP, m_policy.getControlGroup().c_str());
        }
    }

protected:

    bool loopSetup()
    {
        return PolicyManager()->load(m_policy);
    }

    virtual void printLoopHeader()
    {
        CubeSysConfig cfg;

        m_policy.getConfig(&cfg);
        int roleId = GetCubeRole(cfg.role);

        CliPrintf(LABEL_CURRENT_HA, m_policy.getHA());
        if (cfg.ha) {
            if (IsControl(roleId)) {
                CliPrintf(LABEL_CURRENT_CONTROL_VHN, m_policy.getController());
                CliPrintf(LABEL_CURRENT_CONTROL_VIP, m_policy.getControlVip());
                // CliPrintf(LABEL_CURRENT_STORAGE_GROUP, m_policy.getStorageGroup().c_str());
            }
            CliPrintf(LABEL_CURRENT_CONTROL_GROUP, m_policy.getControlGroup().c_str());
        }
    }

    virtual bool doAction(int index)
    {
        CubeSysConfig cfg;
        m_policy.getConfig(&cfg);

        switch(index)
        {
            case 0:
                // Invoke the role menu item builder
                if (m_cubehaChanger.configure(&cfg)) {
                    if (!m_policy.setConfig(cfg))
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
    CliCubeHaChanger m_cubehaChanger;

    // The time policy to be loaded, modified and saved
    CubeSysPolicy m_policy;
};

FIRSTTIME_MODULE(CubeHaModule, FT_ORDER_LAST + 3);

