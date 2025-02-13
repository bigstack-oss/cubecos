// CUBE SDK

#ifndef CLI_CUBEHA_H
#define CLI_CUBEHA_H

#include <hex/parse.h>
#include <hex/cli_util.h>
#include <hex/string_util.h>

#include <arpa/inet.h>
#include "role_cubesys.h"

// Messages
static const char* HA_MSG_INVALID_IPV4_ADDR = "The value entered, %s, is not an IPv4 address.";
static const char* MSG_INVALID_GROUP = "Hostname and Ip Address number mis-matched.";

// Labels
static const char* HA_LABEL_YES = "Yes";
static const char* HA_LABEL_NO = "No";
static const char* LABEL_CONFIG_HA = "High Availabile Cube: ";
static const char* LABEL_CONFIG_CONTROL_VHN = "Specify control virtual Hostname: ";
static const char* LABEL_CONFIG_CONTROL_VIP = "Specify control virtual IP: ";
static const char* LABEL_CONFIG_CONTROL_HOSTS = "Specify control group hostname [HOST,HOST,...]: ";
static const char* LABEL_CONFIG_CONTROL_ADDRS = "Specify control group address [IP,IP,...]: ";
static const char* LABEL_CONFIG_STORAGE_HOSTS = "Specify storage group hostname [HOST,HOST,...]: ";
static const char* LABEL_CONFIG_STORAGE_ADDRS = "Specify storage group address [IP,IP,...]: ";

/**
 * A class to handle the cube role change functionality.
 */
class CliCubeHaChanger
{
public:
    CliCubeHaChanger() {}

    ~CliCubeHaChanger() {}

    // Run the role change operation.
    bool configure(CubeSysConfig *config)
    {
        CliPrintf(LABEL_CONFIG_HA);
        CliList enabledList;
        enabledList.push_back(HA_LABEL_YES);
        enabledList.push_back(HA_LABEL_NO);
        int idx = CliReadListIndex(enabledList);
        if (idx < 0 || idx > 1) {
            return false;
        }

        // 0:YES, 1:NO
        config->ha = (idx == 0);
        int roleId = GetCubeRole(config->role);

        if (config->ha) {
            if (IsControl(roleId)) {
                if(!setController(config)) {
                    return false;
                }
                if(!setControlVip(config)) {
                    return false;
                }
#if 0
                if(!setStorageGroup(config)) {
                    return false;
                }
#endif
            }

            if(!setControlGroup(config)) {
                return false;
            }
        }

        return true;
    }

private:

    bool setController(CubeSysConfig *config)
    {
        std::string hostname;

        if (!CliReadLine(LABEL_CONFIG_CONTROL_VHN, hostname)) {
            return false;
        }

        config->controller = hostname;
        return true;
    }

    bool setControlVip(CubeSysConfig *config)
    {
        std::string vip;

        if (!CliReadLine(LABEL_CONFIG_CONTROL_VIP, vip)) {
            return false;
        }

        struct in_addr v4addr;
        if (!HexParseIP(vip.c_str(), AF_INET, &v4addr)) {
            CliPrintf(HA_MSG_INVALID_IPV4_ADDR, vip.c_str());
            return false;
        }

        config->controlVip = vip;
        return true;
    }

    bool setControlGroup(CubeSysConfig *config)
    {
        std::string controlHosts, controlAddrs;

        if (!CliReadLine(LABEL_CONFIG_CONTROL_HOSTS, controlHosts)) {
            return false;
        }

        if (!CliReadLine(LABEL_CONFIG_CONTROL_ADDRS, controlAddrs)) {
            return false;
        }

        auto hostlist = hex_string_util::split(controlHosts, ',');
        auto iplist = hex_string_util::split(controlAddrs, ',');

        if (hostlist.size() != iplist.size()) {
            CliPrintf(MSG_INVALID_GROUP);
            return false;
        }

        for (size_t i = 0 ; i < iplist.size() ; i++) {
            struct in_addr v4addr;
            if (!HexParseIP(iplist[i].c_str(), AF_INET, &v4addr)) {
                CliPrintf(HA_MSG_INVALID_IPV4_ADDR, iplist[i].c_str());
                return false;
            }
        }

        config->controlHosts = controlHosts;
        config->controlAddrs = controlAddrs;
        return true;
    }

    bool setStorageGroup(CubeSysConfig *config)
    {
        std::string storageHosts, storageAddrs;

        if (!CliReadLine(LABEL_CONFIG_STORAGE_HOSTS, storageHosts)) {
            return false;
        }

        if (!CliReadLine(LABEL_CONFIG_STORAGE_ADDRS, storageAddrs)) {
            return false;
        }

        auto hostlist = hex_string_util::split(storageHosts, ',');
        auto iplist = hex_string_util::split(storageAddrs, ',');

        if (hostlist.size() != iplist.size()) {
            CliPrintf(MSG_INVALID_GROUP);
            return false;
        }

        for (size_t i = 0 ; i < iplist.size() ; i++) {
            struct in_addr v4addr;
            if (!HexParseIP(iplist[i].c_str(), AF_INET, &v4addr)) {
                CliPrintf(HA_MSG_INVALID_IPV4_ADDR, iplist[i].c_str());
                return false;
            }
        }

        config->storageHosts = storageHosts;
        config->storageAddrs = storageAddrs;
        return true;
    }
};

#endif /* endif CLI_CUBEHA_H */

