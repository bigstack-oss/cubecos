// HEX SDK

#include <set>
#include <map>

#include <hex/log.h>
#include <hex/tuning.h>
#include <hex/yml_util.h>

#include <hex/translate_module.h>

#include "include/policy_cubesys.h"

typedef std::set<std::string> IfaceSet;
static IfaceSet netIfSet;

typedef std::map<std::string, std::string> IfaceMap;
static IfaceMap port2label;
static IfaceMap label2port;

// Parse the system settings
static bool
ParseSys(const char* name, const char* value)
{
    HexLogDebugN(3, "parsing name=%s value=%s", name, value);

    const char* p = 0;
    if (HexMatchPrefix(name, "sys.net.if.label.", &p)) {
        port2label[p] = value;  // port2label["eth0"] = IF.1
        label2port[value] = p;  // label2port["IF.1"] = eth0
        netIfSet.insert(p);
    }

    return true;
}

static std::string
GetIfname(const std::string& label)
{
    std::vector<std::string> comp = hex_string_util::split(label, '.');
    if (comp[0] == "IF" && comp.size() >= 2) {
        std::string pif = label2port[comp[0] + "." + comp[1]];
        if (comp.size() == 2)   // physical interface (e.g IF.1, IF.2, etc)
            return pif;
        else if (comp.size() == 3)  // vlan interface (e.g IF.1.100, IF.2.101, etc)
            return pif + "." + comp[2];
    }

    return label;   // bonding or its vlan interface (e.g. cluster, cluster.101, etc)
}

static std::string
GetIfList(const std::string& list)
{
    std::string iflist = "";
    std::vector<std::string> labels = hex_string_util::split(list, ',');

    for (auto& l : labels) {
        iflist += GetIfname(l) + ",";
    }

    hex_string_util::rstrip(iflist, ",");

    return iflist;
}

static bool
ProcessRole(CubeSysConfig &cfg, FILE* settings)
{
    int roleIdx = GetCubeRole(cfg.role);

    HexLogDebug("Processing role config");
    fprintf(settings, "cubesys.role = %s\n", cfg.role.c_str());
    fprintf(settings, "cubesys.domain = %s\n", cfg.domain.c_str());
    fprintf(settings, "cubesys.region = %s\n", cfg.region.c_str());

    if(ControlReq(roleIdx)) {
        fprintf(settings, "cubesys.controller = %s\n", cfg.controller.c_str());
        fprintf(settings, "cubesys.controller.ip = %s\n", cfg.controllerIp.c_str());
    }

    if(IsControl(roleIdx) || IsCompute(roleIdx)) {
        if (cfg.external.length() > 0)
            fprintf(settings, "cubesys.external = %s\n", cfg.external.c_str());
    }

    fprintf(settings, "cubesys.management = %s\n", GetIfname(cfg.mgmt).c_str());

    if(IsCompute(roleIdx)) {
        fprintf(settings, "cubesys.provider = %s\n", GetIfname(cfg.provider).c_str());
        fprintf(settings, "cubesys.overlay = %s\n", GetIfname(cfg.overlay).c_str());
    }

    if(IsControl(roleIdx) || IsCompute(roleIdx) || IsStorage(roleIdx)) {
        fprintf(settings, "cubesys.storage = %s\n", GetIfList(cfg.storage).c_str());
    }

    fprintf(settings, "cubesys.seed = %s\n", cfg.seed.c_str());

    if(IsControl(roleIdx)) {
        fprintf(settings, "cubesys.mgmt.cidr = %s\n", cfg.mgmtCidr.c_str());
    }

    fprintf(settings, "cubesys.ha = %s\n", cfg.ha ? "true" : "false");
    fprintf(settings, "cubesys.saltkey = %s\n", cfg.saltkey ? "true" : "false");

    if (cfg.ha) {
        if(IsControl(roleIdx)) {
            fprintf(settings, "cubesys.controller = %s\n", cfg.controller.c_str());
            fprintf(settings, "cubesys.control.vip = %s\n", cfg.controlVip.c_str());
        }

        fprintf(settings, "cubesys.control.hosts = %s\n", cfg.controlHosts.c_str());
        fprintf(settings, "cubesys.control.addrs = %s\n", cfg.controlAddrs.c_str());
        if (cfg.storageHosts.length())
            fprintf(settings, "cubesys.storage.hosts = %s\n", cfg.storageHosts.c_str());
        if (cfg.storageAddrs.length())
            fprintf(settings, "cubesys.storage.addrs = %s\n", cfg.storageAddrs.c_str());
    }

    return true;
}

// Translate the role policy
static bool
Translate(const char *policy, FILE *settings)
{
    bool status = true;

    HexLogDebug("translate_role policy: %s", policy);

    GNode *yml = InitYml("role");
    CubeSysConfig cfg;

    if (ReadYml(policy, yml) < 0) {
        FiniYml(yml);
        HexLogError("Failed to parse policy file %s", policy);
        return false;
    }

    fprintf(settings, "\n# Cube System Tuning Params\n");

    HexYmlParseString(cfg.role, yml, "role");
    HexYmlParseString(cfg.domain, yml, "domain");
    HexYmlParseString(cfg.region, yml, "region");

    int roleIdx = GetCubeRole(cfg.role);
    if(ControlReq(roleIdx)) {
        HexYmlParseString(cfg.controller, yml, "controller");
        HexYmlParseString(cfg.controllerIp, yml, "controller-ip");
    }

    if(IsControl(roleIdx) || IsCompute(roleIdx)) {
        HexYmlParseString(cfg.external, yml, "external");
    }

    HexYmlParseString(cfg.mgmt, yml, "management");

    if(IsCompute(roleIdx)) {
        HexYmlParseString(cfg.provider, yml, "provider");
        HexYmlParseString(cfg.overlay, yml, "overlay");
    }

    if(IsControl(roleIdx) || IsCompute(roleIdx) || IsStorage(roleIdx)) {
        HexYmlParseString(cfg.storage, yml, "storage");
    }

    HexYmlParseString(cfg.seed, yml, "secret-seed");

    if(IsControl(roleIdx)) {
        HexYmlParseString(cfg.mgmtCidr, yml, "mgmt-cidr");
    }

    HexYmlParseBool(&cfg.saltkey, yml, "saltkey");
    HexYmlParseBool(&cfg.ha, yml, "ha");
    if (cfg.ha) {
        if(IsControl(roleIdx)) {
            HexYmlParseString(cfg.controller, yml, "controller");
            HexYmlParseString(cfg.controlVip, yml, "control-vip");
        }

        HexYmlParseString(cfg.controlHosts, yml, "control-hosts");
        HexYmlParseString(cfg.controlAddrs, yml, "control-addrs");
        HexYmlParseString(cfg.storageHosts, yml, "storage-hosts");
        HexYmlParseString(cfg.storageAddrs, yml, "storage-addrs");
    }

    ProcessRole(cfg, settings);

    FiniYml(yml);

    return status;
}

TRANSLATE_MODULE(cubesys/cubesys1_0, ParseSys, 0, Translate, 0);

