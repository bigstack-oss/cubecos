// CUBE

#include <hex/log.h>
#include <hex/pidfile.h>
#include <hex/filesystem.h>
#include <hex/process.h>
#include <hex/tuning.h>
#include <hex/process_util.h>
#include <hex/string_util.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/logrotate.h>
#include <hex/dryrun.h>

#include <cube/systemd_util.h>
#include <cube/config_file.h>
#include <cube/network.h>
#include <cube/cluster.h>
#include <cube/cubesys.h>

#include "mysql_util.h"
#include "include/role_cubesys.h"

// neutron common
static const char USER[] = "neutron";
static const char GROUP[] = "neutron";
static const char RUNDIR[] = "/run/neutron";
static const char OVN_RUNDIR[] = "/var/run/ovn";

// neutron config files
#define DEF_EXT     ".def"
#define CONF        "/etc/neutron/neutron.conf"
#define ML2_CONF    "/etc/neutron/plugins/ml2/ml2_conf.ini"
#define MD_CONF     "/etc/neutron/plugins/networking-ovn/networking-ovn-metadata-agent.ini"
#define VPNAAS_CONF     "/etc/neutron/neutron_vpnaas.conf"
#define VPN_AGT_CONF    "/etc/neutron/vpn_agent.ini"

#define OVN_NORTHD_CONF     "/etc/sysconfig/ovn-northd"
#define SFLOW_ENABLED       "/etc/appliance/state/sflow_enabled"

static const char SRV_NAME[] = "neutron-server";
static const char MD_NAME[] = "networking-ovn-metadata-agent";
static const char VPN_NAME[] = "neutron-ovn-vpn-agent";
static const char IRONIC_AGENT_NAME[] = "ironic-neutron-agent";

static const char OVS_NAME[] = "openvswitch";
static const char OVNND_NAME[] = "ovn-northd";
static const char OVNCTL_NAME[] = "ovn-controller";

static const char OPENRC[] = "/etc/admin-openrc.sh";
static const char AGENT_CACHE[] = "/etc/cron.d/neutron_agent_cache_renew";

static const char USERPASS[] = "XPrCSFAZu5h98rVM";
static const char METAPASS[] = "HeBlO7sMRH6fYtmC";
static const char DBPASS[] = "KNaHKGg62djyeJ6M";

static const char OSCMD[] = "/usr/bin/openstack";

static Configs cfg;
static Configs ml2Cfg;
static Configs mdCfg;
static Configs vpnaasCfg;
static Configs vpnAgtCfg;

static bool s_bSetup = true;
static bool s_bNetModified = false;
static bool s_bMqModified = false;
static bool s_bCubeModified = false;
static bool s_bNovaModified = false;
static bool s_bKeystoneModified = false;

static bool s_bDbPassChanged = false;
static bool s_bConfigChanged = false;
static bool s_bEndpointChanged = false;
static unsigned s_uOverlayMtu = 1500;

typedef std::map<std::string, ConfigUInt> MtuMap;

static CubeRole_e s_eCubeRole;
static ConfigString s_hostname;
static MtuMap s_Mtu;

// external global variables
CONFIG_GLOBAL_BOOL_REF(IS_MASTER);
CONFIG_GLOBAL_STR_REF(MGMT_IF);
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(EXTERNAL);
CONFIG_GLOBAL_STR_REF(OVERLAY_ADDR);
CONFIG_GLOBAL_STR_REF(PROVIDER_IF);
CONFIG_GLOBAL_STR_REF(OVERLAY_IF);

// private tunings
CONFIG_TUNING_BOOL(NEUTRON_ENABLED, "neutron.enabled", TUNING_UNPUB, "Set to true to enable neutron.", true);
CONFIG_TUNING_STR(NEUTRON_USERPASS, "neutron.user.password", TUNING_UNPUB, "Set neutron user password.", USERPASS, ValidateNone);
CONFIG_TUNING_STR(NEUTRON_METAPASS, "neutron.metadata.password", TUNING_UNPUB, "Set neutron metadata password.", METAPASS, ValidateNone);
CONFIG_TUNING_STR(NEUTRON_DBPASS, "neutron.db.password", TUNING_UNPUB, "Set neutron database password.", DBPASS, ValidateNone);
CONFIG_TUNING_BOOL(NEUTRON_HA_ENABLED, "neutron.ha.enabled", TUNING_UNPUB, "Set to true to enable router and dhcp agent HA.", true);

// public tunigns
CONFIG_TUNING_BOOL(NEUTRON_DEBUG, "neutron.debug.enabled", TUNING_PUB, "Set to true to enable neutron verbose log.", false);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_UINT(NET_IF_MTU);
CONFIG_TUNING_SPEC_STR(RABBITMQ_OPENSTACK_PASSWD);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_DOMAIN);
CONFIG_TUNING_SPEC_STR(CUBESYS_REGION);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_STR(CUBESYS_PROVIDER_EXTRA);
CONFIG_TUNING_SPEC_STR(NOVA_USERPASS);
CONFIG_TUNING_SPEC_STR(KEYSTONE_ADMIN_CLI_PASS);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, NEUTRON_ENABLED);
PARSE_TUNING_BOOL(s_debug, NEUTRON_DEBUG);
PARSE_TUNING_STR(s_neutronPass, NEUTRON_USERPASS);
PARSE_TUNING_STR(s_metaPass, NEUTRON_METAPASS);
PARSE_TUNING_STR(s_dbPass, NEUTRON_DBPASS);
PARSE_TUNING_BOOL(s_netHaEnabled, NEUTRON_HA_ENABLED);
PARSE_TUNING_X_STR(s_mqPass, RABBITMQ_OPENSTACK_PASSWD, 1);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 2);
PARSE_TUNING_X_STR(s_cubeDomain, CUBESYS_DOMAIN, 2);
PARSE_TUNING_X_STR(s_cubeRegion, CUBESYS_REGION, 2);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 2);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 2);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 2);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 2);
PARSE_TUNING_X_STR(s_providerExtra, CUBESYS_PROVIDER_EXTRA, 2);

// FIXME: circular issue
//PARSE_TUNING_X_STR(s_novaPass, NOVA_USERPASS, 3);
static ConfigString s_novaPass("8YdO3T0l3qaEgdjT");

PARSE_TUNING_X_STR(s_adminCliPass, KEYSTONE_ADMIN_CLI_PASS, 4);
PARSE_TUNING_X_STR(s_ironicPass, IRONIC_USERPASS, 5);

static LogRotateConf log_conf("ovn", "/var/log/ovn/*.log", DAILY, 128, 0, true);

typedef std::map<std::string, std::string> IfaceMap;
static IfaceMap label2port;

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
GetExtraProvider(const std::string& providerExtra)
{
    std::string ep = "";

    if (providerExtra.size() == 0)
        return ep;

    auto providers = hex_string_util::split(providerExtra, ',');
    for (auto p : providers) {
        auto comp = hex_string_util::split(p, ':');
        ep += "," + comp[1];
    }

    return ep;
}

static bool
CronAgentCacheRenew()
{
    if(IsControl(s_eCubeRole)) {
        FILE *fout = fopen(AGENT_CACHE, "w");
        if (!fout) {
            HexLogError("Unable to write %s agent cache renew-er: %s", USER, AGENT_CACHE);
            return false;
        }

        fprintf(fout, "*/5 * * * * root " HEX_SDK " os_neutron_agent_cache_renew\n");
        fclose(fout);

        if(HexSetFileMode(AGENT_CACHE, "root", "root", 0644) != 0) {
            HexLogError("Unable to set file %s mode/permission", AGENT_CACHE);
            return false;
        }
    }
    else {
        unlink(AGENT_CACHE);
    }

    return true;
}

static std::string
GetOvnRemote(const std::string &sharedId, const std::string port)
{
    return "tcp:" + sharedId + ":" + port;
}

// depends on mysqld (called inside commit())
static bool
SetupCheck()
{
    if (!IsControl(s_eCubeRole))
        return true;

    if(!MysqlUtilIsDbExist("neutron")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE neutron") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY 'neutron_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY 'neutron_dbpass'")) {
            return false;
        }

        s_bSetup = false;
    }

    return true;
}

static bool
SetupOvn(std::string hostname, std::string overlayAddr, std::string ovnRemote, std::string provider, std::string providerExtra)
{
    HexLogInfo("Setting up ovs/ovn");

    if (IsControl(s_eCubeRole) || IsCompute(s_eCubeRole)) {
        HexUtilSystemF(0, 0, "ovs-vsctl set open_vswitch . external-ids:hostname='%s'", hostname.c_str());
        HexUtilSystemF(0, 0, "ovs-vsctl set-manager ptcp:6640");
    }

    if (IsCompute(s_eCubeRole)) {
        HexUtilSystemF(0, 0, "ovs-vsctl set open_vswitch . external-ids:ovn-cms-options=enable-chassis-as-gw");
        HexUtilSystemF(0, 0, "ovs-vsctl set open_vswitch . external-ids:ovn-remote=%s", ovnRemote.c_str());
        HexUtilSystemF(0, 0, "ovs-vsctl set open_vswitch . external-ids:ovn-encap-type=geneve,vxlan");
        HexUtilSystemF(0, 0, "ovs-vsctl set open_vswitch . external-ids:ovn-encap-ip=%s", overlayAddr.c_str());

        std::string mappings = "provider:provider";

        if (providerExtra.size() > 0) {
            auto providers = hex_string_util::split(providerExtra, ',');
            for (auto p : providers) {
                auto comp = hex_string_util::split(p, ':');
                mappings += "," + comp[1] + ":" + comp[1];
            }
        }

        HexUtilSystemF(0, 0, "ovs-vsctl set open_vswitch . external-ids:ovn-bridge-mappings=%s", mappings.c_str());
        HexUtilSystemF(0, 0, HEX_SDK " ovn_bridge_phy_port_add_v4 provider %s", provider.c_str());

        if (providerExtra.size() > 0) {
            auto providers = hex_string_util::split(providerExtra, ',');
            for (auto p : providers) {
                auto comp = hex_string_util::split(p, ':');
                HexUtilSystemF(0, 0, HEX_SDK " ovn_bridge_phy_port_add_v4 %s %s", comp[1].c_str(), GetIfname(comp[0]).c_str());
            }
        }
    }

    return true;
}

static bool
SetupNeutron(std::string domain, std::string password)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Setting up neutron");

    // Populate the neutron service database
    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"neutron-db-manage --config-file %s --config-file %s upgrade head\" %s",
                         CONF, ML2_CONF, USER);

    // Populate the neutron vpnaas service database
    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"neutron-db-manage --subproject neutron-vpnaas upgrade head\" %s", USER);

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // Create the neutron service credentials
    HexUtilSystemF(0, 0, "%s %s user create --domain %s --password %s neutron", env.c_str(), OSCMD, domain.c_str(), password.c_str());
    HexUtilSystemF(0, 0, "%s %s role add --project service --user neutron admin", env.c_str(), OSCMD);

    // Create the service entity
    HexUtilSystemF(0, 0, "%s %s service create --name %s "
                         "--description \"OpenStack Networking\" network",
                         env.c_str(), OSCMD, USER);

    return true;
}

static bool
UpdateEndpoint(std::string endpoint, std::string external, std::string region)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Updating neutron endpoint");

    std::string pub = "http://" + external + ":9696";
    std::string adm = "http://" + endpoint + ":9696";
    std::string intr = "http://" + endpoint + ":9696";

    HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_update %s %s %s %s %s",
                         "network", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

    return true;
}

static bool
UpdateDbConn(std::string sharedId, std::string password)
{
    if (IsControl(s_eCubeRole)) {
        std::string dbconn = "mysql+pymysql://neutron:";
        dbconn += password;
        dbconn += "@";
        dbconn += sharedId;
        dbconn += "/neutron";

        cfg["database"].clear();
        cfg["database"]["connection"] = dbconn;
    }

    return true;
}

static bool
UpdateMqConn(const bool ha, std::string sharedId, std::string password, std::string ctrlAddrs)
{
    std::string dbconn = RabbitMqServers(ha, sharedId, password, ctrlAddrs);
    if (IsControl(s_eCubeRole)) {
        cfg["DEFAULT"]["transport_url"] = dbconn;
        cfg["DEFAULT"]["rpc_response_timeout"] = "1200";

        if (ha) {
            cfg["oslo_messaging_rabbit"]["rabbit_retry_interval"] = "1";
            cfg["oslo_messaging_rabbit"]["rabbit_retry_backoff"] = "2";
            cfg["oslo_messaging_rabbit"]["amqp_durable_queues"] = "true";
            cfg["oslo_messaging_rabbit"]["rabbit_ha_queues"] = "true";
        }


    }

    if (IsCompute(s_eCubeRole)) {
        vpnAgtCfg["DEFAULT"]["transport_url"] = dbconn;

        if (ha) {
            vpnAgtCfg["oslo_messaging_rabbit"]["rabbit_retry_interval"] = "1";
            vpnAgtCfg["oslo_messaging_rabbit"]["rabbit_retry_backoff"] = "2";
            vpnAgtCfg["oslo_messaging_rabbit"]["amqp_durable_queues"] = "true";
            vpnAgtCfg["oslo_messaging_rabbit"]["rabbit_ha_queues"] = "true";
        }
    }

    return true;
}

static bool
UpdateMyIp(std::string myIp)
{
    if (IsControl(s_eCubeRole)) {
        cfg["DEFAULT"]["bind_host"] = myIp;
    }

    if (IsCompute(s_eCubeRole)) {
        mdCfg["ovs"]["ovsdb_connection"] = "tcp:" + myIp + ":6640";
        vpnAgtCfg["ovs"]["ovsdb_connection"] = "tcp:" + myIp + ":6640";
    }

    return true;
}

static bool
UpdateSharedId(std::string sharedId, std::string ovnnb, std::string ovnsb)
{
    if (IsControl(s_eCubeRole)) {
        cfg["keystone_authtoken"]["memcached_servers"] = sharedId + ":11211";
        cfg["keystone_authtoken"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        cfg["keystone_authtoken"]["auth_url"] = "http://" + sharedId + ":5000";
        cfg["nova"]["auth_url"] = "http://" + sharedId + ":5000";
        cfg["octavia"]["base_url"] = "http://" + sharedId + ":9876";
        cfg["service_auth"]["auth_url"] = "http://" + sharedId + ":5000/v2.0";
        cfg["designate"]["url"] = "http://" + sharedId + ":9001/v2";
        cfg["designate"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        cfg["designate"]["admin_auth_url"] = "http://" + sharedId + ":5000";
        cfg["oslo_messaging_notifications"]["transport_url"] = "kafka://" + sharedId + ":9095";

        ml2Cfg["ovn"]["ovn_nb_connection"] = ovnnb;
        ml2Cfg["ovn"]["ovn_sb_connection"] = ovnsb;
    }

    if (IsCompute(s_eCubeRole)) {
        mdCfg["DEFAULT"]["nova_metadata_host"] = sharedId;
        mdCfg["ovn"]["ovn_sb_connection"] = ovnsb;
        vpnAgtCfg["ovn"]["ovn_sb_connection"] = ovnsb;
    }

    return true;
}

static bool
UpdateDebug(bool enabled)
{
    std::string value = enabled ? "true" : "false";
    cfg["DEFAULT"]["debug"] = value;
    ml2Cfg["DEFAULT"]["debug"] = value;
    mdCfg["DEFAULT"]["debug"] = value;

    return true;
}

static bool
UpdateCfg(std::string domain, std::string region, std::string password,
          std::string novapass, std::string metapass, std::string clipass, unsigned overlayMtu, std::string ep)
{
    if (IsControl(s_eCubeRole)) {
        cfg["DEFAULT"]["auth_strategy"] = "keystone";
        cfg["DEFAULT"]["notify_nova_on_port_status_changes"] = "true";
        cfg["DEFAULT"]["notify_nova_on_port_data_changes"] = "true";
        cfg["DEFAULT"]["global_physnet_mtu"] = std::to_string(overlayMtu);

        cfg["keystone_authtoken"].clear();
        cfg["keystone_authtoken"]["auth_type"] = "password";
        cfg["keystone_authtoken"]["project_domain_name"] = domain.c_str();
        cfg["keystone_authtoken"]["user_domain_name"] = domain.c_str();
        cfg["keystone_authtoken"]["project_name"] = "service";
        cfg["keystone_authtoken"]["username"] = "neutron";
        cfg["keystone_authtoken"]["password"] = password.c_str();

        cfg["oslo_concurrency"]["lock_path"] = RUNDIR;
        cfg["DEFAULT"]["core_plugin"] = "neutron.plugins.ml2.plugin.Ml2Plugin";
        cfg["DEFAULT"]["service_plugins"] = "neutron.services.ovn_l3.plugin.OVNL3RouterPlugin,ovn-vpnaas";
        cfg["DEFAULT"]["allow_overlapping_ips"] = "true";
        cfg["DEFAULT"]["notify_nova_on_port_status_changes"] = "true";
        cfg["DEFAULT"]["notify_nova_on_port_data_changes"] = "true";
        cfg["DEFAULT"]["dns_domain"] = "cube.local.";
        cfg["DEFAULT"]["external_dns_driver"] = "designate";

        cfg["service_auth"]["admin_user"] = "admin_cli";
        cfg["service_auth"]["admin_password"] = clipass;
        cfg["service_auth"]["admin_user_domain"] = "default";
        cfg["service_auth"]["admin_tenant_name"] = "admin";
        cfg["service_auth"]["auth_version"] = "2";

        cfg["nova"]["auth_type"] = "password";
        cfg["nova"]["project_domain_name"] = domain.c_str();
        cfg["nova"]["user_domain_name"] = domain.c_str();
        cfg["nova"]["region_name"] = region.c_str();
        cfg["nova"]["project_name"] = "service";
        cfg["nova"]["username"] = "nova";
        cfg["nova"]["password"] = novapass.c_str();

        cfg["designate"]["admin_username"] = "neutron";
        cfg["designate"]["admin_password"] = password;
        cfg["designate"]["admin_tenant_name"] = "service";
        cfg["designate"]["project_domain_id"] = domain;
        cfg["designate"]["user_domain_id"] = domain;
        cfg["designate"]["project_name"] = "service";
        cfg["designate"]["username"] = "neutron";
        cfg["designate"]["password"] = password;
        cfg["designate"]["allow_reverse_dns_lookup"] = "true";
        cfg["designate"]["ipv4_ptr_zone_prefix_size"] = "24";
        cfg["designate"]["ipv6_ptr_zone_prefix_size"] = "116";

        if (s_ha && s_netHaEnabled) {
            cfg["DEFAULT"]["l3_ha"] = "true";   // enable VRRP
            cfg["DEFAULT"]["l3_ha_net_cidr"] = "169.254.192.0/18";
            cfg["DEFAULT"]["max_l3_agents_per_router"] = "2";
            cfg["DEFAULT"]["dhcp_agents_per_network"] = "2";   // enable DHCP HA
        }

        cfg["oslo_messaging_notifications"]["driver"] = "messagingv2";

        ml2Cfg["ml2"]["type_drivers"] = "local,flat,vlan,geneve";
        ml2Cfg["ml2"]["tenant_network_types"] = "geneve";
        ml2Cfg["ml2"]["mechanism_drivers"] = "ovn,baremetal";
        ml2Cfg["ml2"]["extension_drivers"] = "port_security,dns_domain_ports";
        ml2Cfg["ml2"]["overlay_ip_version"] = "4";
        ml2Cfg["ml2"]["path_mtu"] = std::to_string(overlayMtu);
        ml2Cfg["ml2_type_flat"]["flat_networks"] = "provider" + ep;
        ml2Cfg["ml2_type_vlan"]["network_vlan_ranges"] = "provider" + ep;

        ml2Cfg["ml2_type_geneve"]["vni_ranges"] = "1:4095";
        ml2Cfg["ml2_type_geneve"]["max_header_size"] = "38";
        ml2Cfg["securitygroup"]["enable_ipset"] = "true";

        ml2Cfg["ovn"]["ovn_l3_scheduler"] = "leastloaded";
        ml2Cfg["ovn"]["ovn_metadata_enabled"] = "true";
        ml2Cfg["ovn"]["enable_distributed_floating_ip"] = "true";
        ml2Cfg["ovn"]["ovsdb_probe_interval"] = "600000";
        ml2Cfg["ovn"]["ovn_dhcp4_global_options"] = "classless_static_route:{169.254.169.254/32}";

        vpnaasCfg["service_providers"]["service_provider"] = "VPN:openswan:neutron_vpnaas.services.vpn.service_drivers.ovn_ipsec.IPsecOvnVPNDriver:default";
    }

    if (IsCompute(s_eCubeRole)) {
        mdCfg["DEFAULT"]["metadata_proxy_shared_secret"] = metapass.c_str();
        mdCfg["agent"]["root_helper"] = "sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf";
        mdCfg["agent"]["root_helper_daemon"] = "sudo /usr/bin/neutron-rootwrap-daemon /etc/neutron/rootwrap.conf";
        mdCfg["ovs"]["ovsdb_timeout"] = "30";
        vpnAgtCfg["DEFAULT"]["interface_driver"] = "neutron.agent.linux.interface.OVSInterfaceDriver";
        vpnAgtCfg["ipsec"]["enable_detailed_logging"] = "true";
        vpnAgtCfg["vpnagent"]["vpn_device_driver"] = "neutron_vpnaas.services.vpn.device_drivers.ovn_ipsec.OvnLibreSwanDriver";
        vpnAgtCfg["AGENT"]["root_helper"] = "sudo neutron-rootwrap /etc/neutron/rootwrap.conf";
    }

    if (IsControl(s_eCubeRole)) {
        std::string workers = std::to_string(GetControlWorkers(IsConverged(s_eCubeRole), IsEdge(s_eCubeRole)));
        cfg["DEFAULT"]["api_workers"] = workers;
        mdCfg["DEFAULT"]["metadata_workers"] = workers;
    }

    return true;
}

static bool
UpdateOvnConfig()
{
    if (!IsControl(s_eCubeRole))
        return true;

    FILE *fout = fopen(OVN_NORTHD_CONF, "w");
    if (!fout) {
        HexLogError("Unable to write config: %s", OVN_NORTHD_CONF);
        return false;
    }

    std::string conf = "";

    conf += "--db-nb-create-insecure-remote=yes ";
    conf += "--db-sb-create-insecure-remote=yes ";

    fprintf(fout, "OVN_NORTHD_OPTS=\"%s\"\n", conf.c_str());
    fclose(fout);

    return true;
}

static bool
OvnService(bool enabled, bool isMaster, bool forceRun, bool ha)
{
    if (IsControl(s_eCubeRole) || IsCompute(s_eCubeRole)) {
        SystemdCommitService(enabled , OVS_NAME, true);     // openvswitch
    }

    if (isMaster) {
        if (forceRun || !ha)
            SystemdCommitService(enabled , OVNND_NAME, true);   // ovn-northd
        else if (ha)
            HexUtilSystemF(0, 0, "pcs resource restart ovndb_servers-clone");
    }

    if (IsCompute(s_eCubeRole)) {
        HexSetFileMode(OVN_RUNDIR, "openvswitch", "openvswitch", 0755);
        SystemdCommitService(enabled , OVNCTL_NAME, true);  // ovn-controller
    }

    return true;
}

static bool
NeutronService(bool enabled)
{
    if (IsControl(s_eCubeRole)) {
        SystemdCommitService(enabled , SRV_NAME, true);     // neutron-server
    }

    if (IsCompute(s_eCubeRole)) {
        SystemdCommitService(enabled , MD_NAME, true);      // networking-ovn-metadata-agent
        SystemdCommitService(enabled , VPN_NAME, true);     // neutron-ovn-vpn-agent
    }

    return true;
}

static bool
Init()
{
    if (HexMakeDir(RUNDIR, USER, GROUP, 0755) != 0)
        return false;

    if (HexMakeDir(OVN_RUNDIR, "openvswitch", "openvswitch", 0755) != 0)
        return false;

    // load neutron configurations
    if (!LoadConfig(CONF DEF_EXT, SB_SEC_RFMT, '=', cfg)) {
        HexLogError("failed to load neutron config file %s", CONF);
        return false;
    }

    // load ml2 configurations
    if (!LoadConfig(ML2_CONF DEF_EXT, SB_SEC_RFMT, '=', ml2Cfg)) {
        HexLogError("failed to load ml2 config file %s", ML2_CONF);
        return false;
    }

    // load metadata configurations
    if (!LoadConfig(MD_CONF DEF_EXT, SB_SEC_RFMT, '=', mdCfg)) {
        HexLogError("failed to load metadata config file %s", MD_CONF);
        return false;
    }

    // load vpnaas configurations
    if (!LoadConfig(VPNAAS_CONF DEF_EXT, SB_SEC_RFMT, '=', vpnaasCfg)) {
        HexLogError("failed to load vpnaas config file %s", VPNAAS_CONF);
        return false;
    }

    // load vpn agent configurations
    if (!LoadConfig(VPN_AGT_CONF DEF_EXT, SB_SEC_RFMT, '=', vpnAgtCfg)) {
        HexLogError("failed to load vpn agent config file %s", VPN_AGT_CONF);
        return false;
    }

    return true;
}


static bool
Parse(const char *name, const char *value, bool isNew)
{
    bool r = true;

    TuneStatus s = ParseTune(name, value, isNew);
    if (s == TUNE_INVALID_NAME) {
        HexLogWarning("Unknown settings name \"%s\" = \"%s\" ignored", name, value);
    }
    else if (s == TUNE_INVALID_VALUE) {
        HexLogError("Invalid settings value \"%s\" = \"%s\"", name, value);
        r = false;
    }
    return r;
}

static bool
ParseNet(const char *name, const char *value, bool isNew)
{
    const char* p = 0;

    if (strcmp(name, NET_HOSTNAME) == 0) {
        s_hostname.parse(value, isNew);
    }
    else if (HexMatchPrefix(name, NET_IF_MTU.format.c_str(), &p)) {
        ConfigUInt& m = s_Mtu[p];
        m.parse(value, isNew);
    }

    return true;
}

static bool
ParseRabbitMQ(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 1);
    return true;
}

static bool
ParseCube(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 2);
    return true;
}

static bool
ParseNova(const char *name, const char *value, bool isNew)
{
    // FIXME ParseTune(name, value, isNew, 3);
    return true;
}

static bool
ParseSys(const char* name, const char* value, bool isNew)
{
    const char* p = 0;
    if (HexMatchPrefix(name, "sys.net.if.label.", &p)) {
        label2port[value] = p;  // label2port["IF.1"] = eth0
    }

    return true;
}

static bool
ParseKeystone(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 4);
    return true;
}

static void
NotifyNet(bool modified)
{
    s_bNetModified = s_hostname.modified();
}

static void
NotifyMQ(bool modified)
{
    s_bMqModified = IsModifiedTune(1);
}

static void
NotifyCube(bool modified)
{
    s_bCubeModified = IsModifiedTune(2);
    s_eCubeRole = GetCubeRole(s_cubeRole);
}

static void
NotifyNova(bool modified)
{
    s_bNovaModified = s_novaPass.modified();
}

static void
NotifyKeystone(bool modified)
{
    s_bKeystoneModified = IsModifiedTune(4);
}

static void
UpdateOverlayMTU()
{
    std::string overlay = G(OVERLAY_IF);

    for (auto& m : s_Mtu) {
        std::string ifname = m.first;
        std::string pIf = GetParentIf(ifname);
        ConfigUInt& mtu = m.second;

        if (pIf == overlay && mtu.modified()) {
            s_uOverlayMtu = mtu >= 68 ? mtu : s_uOverlayMtu;
            s_bConfigChanged = true;
        }
    }
}

static bool
CommitCheck(bool modified, int dryLevel)
{
    UpdateOverlayMTU();

    if (IsBootstrap()) {
        s_bConfigChanged = true;
        return true;
    }

    s_bDbPassChanged = s_dbPass.modified() | s_bCubeModified;

    s_bConfigChanged = modified | s_bMqModified | s_bNovaModified |
                s_bCubeModified | s_bKeystoneModified | s_bNetModified |
               G_MOD(IS_MASTER) | G_MOD(MGMT_ADDR) | G_MOD(SHARED_ID) |
            G_MOD(OVERLAY_ADDR) | G_MOD(PROVIDER_IF);

    s_bEndpointChanged = s_bCubeModified | G_MOD(SHARED_ID) | G_MOD(EXTERNAL);

    return s_bDbPassChanged | s_bConfigChanged | s_bEndpointChanged;
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    bool isMaster = G(IS_MASTER);
    std::string myIp = G(MGMT_ADDR);
    std::string sharedId = G(SHARED_ID);
    std::string external = G(EXTERNAL);
    std::string overlayAddr = G(OVERLAY_ADDR);
    std::string provider = G(PROVIDER_IF);

    std::string novaPass = GetSaltKey(s_saltkey, s_novaPass.newValue(), s_seed.newValue());
    std::string neutronPass = GetSaltKey(s_saltkey, s_neutronPass.newValue(), s_seed.newValue());
    std::string metaPass = GetSaltKey(s_saltkey, s_metaPass.newValue(), s_seed.newValue());
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass.newValue(), s_seed.newValue());
    std::string mqPass = GetSaltKey(s_saltkey, s_mqPass.newValue(), s_seed.newValue());
    std::string adminCliPass = GetSaltKey(s_saltkey, s_adminCliPass.newValue(), s_seed.newValue());
    std::string ovnNbRemote = GetOvnRemote(sharedId, "6641");
    std::string ovnSbRemote = GetOvnRemote(sharedId, "6642");

    SetupCheck();
    if (!s_bSetup) {
        s_bDbPassChanged = true;
        s_bEndpointChanged = true;
    }

    // 1. System Config
    if (s_bDbPassChanged && IsControl(s_eCubeRole))
        MysqlUtilUpdateDbPass(USER, dbPass.c_str());

    // 2. Service Config
    if (s_bConfigChanged) {
        UpdateCfg(s_cubeDomain.newValue(), s_cubeRegion.newValue(),
                  neutronPass, novaPass, metaPass, adminCliPass,
                  s_uOverlayMtu, GetExtraProvider(s_providerExtra));
        UpdateSharedId(sharedId, ovnNbRemote, ovnSbRemote);
        UpdateMyIp(myIp);
        UpdateDbConn(sharedId, dbPass);
        UpdateMqConn(s_ha, sharedId, mqPass, s_ctrlAddrs.newValue());
        UpdateDebug(s_debug);

        // write back to neutron config files
        WriteConfig(CONF, SB_SEC_WFMT, '=', cfg);
        WriteConfig(ML2_CONF, SB_SEC_WFMT, '=', ml2Cfg);
        WriteConfig(MD_CONF, SB_SEC_WFMT, '=', mdCfg);
        WriteConfig(VPNAAS_CONF, SB_SEC_WFMT, '=', vpnaasCfg);
        WriteConfig(VPN_AGT_CONF, SB_SEC_WFMT, '=', vpnAgtCfg);

        // update ovn-northd config
        UpdateOvnConfig();
    }

    // 3. Service Setup
    if (!s_bSetup)
        SetupNeutron(s_cubeDomain.newValue(), neutronPass);

    // check for db migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_neutron_db");

    if (s_bEndpointChanged)
        UpdateEndpoint(sharedId, external, s_cubeRegion.newValue());

    // 4. Service kickoff
    bool forceRun = !CubeSysCommitAll();
    OvnService(s_enabled, isMaster, forceRun, s_ha);
    SetupOvn(s_hostname, overlayAddr, ovnSbRemote, provider, s_providerExtra);

    // sync for neutron ovn db
    HexUtilSystemF(0, 0, HEX_SDK " migrate_neutron_ovn_sync");

    NeutronService(s_enabled);
    WriteLogRotateConf(log_conf);

    // stop force run ovn-northd since it will later be managed by pacemaker in HA mode
    if (forceRun && s_ha && isMaster)
        SystemdCommitService(false, OVNND_NAME);

    CronAgentCacheRenew();

    return true;
}

static bool
CommitLast(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = s_enabled && IsControl(s_eCubeRole);
    bool isHaMaster = s_ha && G(IS_MASTER);

    // restart neutron-server since ovn-northd is now managed by pacemaker
    if (enabled && isHaMaster) {
        SystemdCommitService(enabled , SRV_NAME, true);
    }

    if (access(SFLOW_ENABLED, F_OK) == 0) {
        std::string mgmtIf = G(MGMT_IF);
        std::string sharedId = G(SHARED_ID);
        HexUtilSystemF(0, 0, HEX_SDK " ovn_bridge_sflow_enable %s %s", mgmtIf.c_str(), sharedId.c_str());
    }

    return true;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_neutron\n", HexLogProgramName());
}

static int
RestartMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartUsage();
        return EXIT_FAILURE;
    }

    bool isMaster = G(IS_MASTER);
    std::string sharedId = G(SHARED_ID);
    std::string overlayAddr = G(OVERLAY_ADDR);
    std::string provider = G(PROVIDER_IF);

    OvnService(s_enabled, isMaster, false, s_ha);
    SetupOvn(s_hostname, overlayAddr, sharedId, provider, s_providerExtra);

    NeutronService(s_enabled);

    return EXIT_SUCCESS;
}

static void
EnableSflowUsage(void)
{
    fprintf(stderr, "Usage: %s enable_sflow\n", HexLogProgramName());
}

static int
EnableSflowMain(int argc, char* argv[])
{
    if (argc != 1) {
        EnableSflowUsage();
        return EXIT_FAILURE;
    }

    std::string mgmtIf = G(MGMT_IF);
    std::string sharedId = G(SHARED_ID);

    HexUtilSystemF(0, 0, HEX_SDK " ovn_bridge_sflow_enable %s %s", mgmtIf.c_str(), sharedId.c_str());

    return EXIT_SUCCESS;
}

static void
DisableSflowUsage(void)
{
    fprintf(stderr, "Usage: %s disable_sflow\n", HexLogProgramName());
}

static int
DisableSflowMain(int argc, char* argv[])
{
    if (argc != 1) {
        DisableSflowUsage();
        return EXIT_FAILURE;
    }

    HexUtilSystemF(0, 0, HEX_SDK " ovn_bridge_sflow_disable");

    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(restart_neutron, RestartMain, RestartUsage);
CONFIG_COMMAND_WITH_SETTINGS(enable_sflow, EnableSflowMain, EnableSflowUsage);
CONFIG_COMMAND_WITH_SETTINGS(disable_sflow, DisableSflowMain, DisableSflowUsage);

CONFIG_MODULE(neutron, Init, Parse, 0, 0, Commit);
CONFIG_MODULE(neutron_last, 0, 0, 0, 0, CommitLast);
CONFIG_REQUIRES(neutron_last, pacemaker_last);
CONFIG_LAST(neutron_last);

// startup sequence
CONFIG_REQUIRES(neutron, memcache);

// extra tunings
CONFIG_OBSERVES(neutron, sys, ParseSys, 0);
CONFIG_OBSERVES(neutron, net, ParseNet, NotifyNet);
CONFIG_OBSERVES(neutron, rabbitmq, ParseRabbitMQ, NotifyMQ);
CONFIG_OBSERVES(neutron, cubesys, ParseCube, NotifyCube);
CONFIG_OBSERVES(neutron, nova, ParseNova, NotifyNova);
CONFIG_OBSERVES(neutron, keystone, ParseKeystone, NotifyKeystone);

CONFIG_MIGRATE(neutron, "/etc/openvswitch/");
CONFIG_MIGRATE(neutron, "/var/lib/ovn");

