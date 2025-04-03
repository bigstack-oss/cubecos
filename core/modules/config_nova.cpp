// CUBE

#include <sys/sysinfo.h>

#include <thread>

#include <hex/log.h>
#include <hex/pidfile.h>
#include <hex/filesystem.h>
#include <hex/process.h>
#include <hex/process_util.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>

#include <cube/config_file.h>
#include <cube/cluster.h>
#include <cube/systemd_util.h>

#include "mysql_util.h"
#include "include/role_cubesys.h"

// nova config files
#define DEF_EXT     ".def"
#define CONF        "/etc/nova/nova.conf"
#define IRONIC_CONF        "/etc/nova/nova-ironic.conf"
#define PLA_CONF    "/etc/placement/placement.conf"

#define SSL_KEYFILE     "/var/lib/nova/certs/server.pem"
#define SSL_KEYFILE_SRC "/var/www/certs/server.pem"
#define NOVA_SSH_KEY    "/var/lib/nova/.ssh/id_rsa"

static const char USER[] = "nova";
static const char GROUP[] = "nova";
static const char PLA_USER[] = "placement";
static const char VOLUME[] = "ephemeral-vms";

// nova common
static const char RUNDIR[] = "/run/nova";
static const char CERTDIR[] = "/var/lib/nova/certs";
static const char NOVA_SSH[] = "/var/lib/nova/.ssh";
static const char NOVA_CEPH_LOG[] = "/var/log/qemu/";

static const char API_NAME[] = "openstack-nova-api";
static const char SCHL_NAME[] = "openstack-nova-scheduler";
static const char CNTR_NAME[] = "openstack-nova-conductor";
static const char VNCP_NAME[] = "openstack-nova-novncproxy";
static const char SPICEP_NAME[] = "nova-spicehtml5proxy";
static const char ISCSI_NAME[] = "iscsid";
static const char CMP_NAME[] = "openstack-nova-compute";
static const char QEMU_GA[] = "qemu-guest-agent";
static const char MULTIPATH_CONF[] = "/etc/multipath.conf";
static const char MULTIPATHD[] = "multipathd";

static const char OPENRC[] = "/etc/admin-openrc.sh";

static const char USERPASS[] = "8YdO3T0l3qaEgdjT";
static const char PLACEPASS[] = "TXh08jAWj1gDdd82";
static const char DBPASS[] = "ZEuDgxtp6TuMB2gc";
static const char PLADBPASS[] = "WsBrzP5t49k4LqEo";

static const char OSCMD[] = "/usr/bin/openstack";

static ConfigString s_hostname;

static Configs cfg;
static Configs plaCfg;
static Configs ironicCfg;

static bool s_bSetup = true;
static bool s_bPlaSetup = true;

static bool s_bNetModified = false;
static bool s_bMqModified = false;
static bool s_bCubeModified = false;
static bool s_bNeutronModified = false;
static bool s_bIronicModified = false;

static bool s_bDbPassChanged = false;
static bool s_bPlaDbPassChanged = false;
static bool s_bConfigChanged = false;
static bool s_bEndpointChanged = false;
static bool s_bCellChanged = false;

static CubeRole_e s_eCubeRole;

// external global variables
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(CTRL_IP);
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(EXTERNAL);

// private tunings
CONFIG_TUNING_BOOL(NOVA_ENABLED, "nova.enabled", TUNING_UNPUB, "Set to true to enable nova.", true);
CONFIG_TUNING_STR(NOVA_USERPASS, "nova.user.password", TUNING_UNPUB, "Set nova user password.", USERPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(NOVA_PLACEPASS, "nova.placement.password", TUNING_UNPUB, "Set placement user password.", PLACEPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(NOVA_DBPASS, "nova.db.password", TUNING_UNPUB, "Set nova database password.", DBPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(NOVA_PLA_DBPASS, "nova.placement.db.password", TUNING_UNPUB, "Set placement database password.", DBPASS, ValidateRegex, DFT_REGEX_STR);

// public tunigns
CONFIG_TUNING_BOOL(NOVA_DEBUG, "nova.debug.enabled", TUNING_PUB, "Set to true to enable nova verbose log.", false);
CONFIG_TUNING_UINT(NOVA_RESV_HOST_VCPU, "nova.control.host.vcpu", TUNING_PUB, "Amount of vcpu to reserve for the control host.",
                   0, 0, 128);
CONFIG_TUNING_UINT(NOVA_RESV_HOST_MEM, "nova.control.host.memory", TUNING_PUB, "Amount of memory in MB to reserve for the control host.",
                   0, 0, 524288);
CONFIG_TUNING_STR(NOVA_GPU_TYPE, "nova.gpu.type", TUNING_PUB, "Specifiy a supported gpu type instances would get.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(NOVA_OC_CPU_RATIO, "nova.overcommit.cpu.ratio", TUNING_PUB, "Specifiy an allowed CPU overcommitted ratio.", "16.0", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(NOVA_OC_RAM_RATIO, "nova.overcommit.ram.ratio", TUNING_PUB, "Specifiy an allowed RAM overcommitted ratio.", "1.0", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(NOVA_OC_DISK_RATIO, "nova.overcommit.disk.ratio", TUNING_PUB, "Specifiy an allowed DISK overcommitted ratio.", "1.5", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(NOVA_HW_TYPE, "nova.hardware.type", TUNING_PUB, "Set default hardware type for hypervisor.", "q35", ValidateRegex, DFT_REGEX_STR);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(RABBITMQ_OPENSTACK_PASSWD);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_DOMAIN);
CONFIG_TUNING_SPEC_STR(CUBESYS_REGION);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);
CONFIG_TUNING_SPEC_STR(NEUTRON_USERPASS);
CONFIG_TUNING_SPEC_STR(NEUTRON_METAPASS);
CONFIG_TUNING_SPEC_STR(IRONIC_USERPASS);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, NOVA_ENABLED);
PARSE_TUNING_BOOL(s_debug, NOVA_DEBUG);
PARSE_TUNING_STR(s_novaPass, NOVA_USERPASS);
PARSE_TUNING_STR(s_placePass, NOVA_PLACEPASS);
PARSE_TUNING_STR(s_dbPass, NOVA_DBPASS);
PARSE_TUNING_STR(s_plaDbPass, NOVA_PLA_DBPASS);
PARSE_TUNING_UINT(s_resvHostVcpu, NOVA_RESV_HOST_VCPU);
PARSE_TUNING_UINT(s_resvHostMem, NOVA_RESV_HOST_MEM);
PARSE_TUNING_STR(s_gpuType, NOVA_GPU_TYPE);
PARSE_TUNING_STR(s_ocCpuRatio, NOVA_OC_CPU_RATIO);
PARSE_TUNING_STR(s_ocRamRatio, NOVA_OC_RAM_RATIO);
PARSE_TUNING_STR(s_ocDiskRatio, NOVA_OC_DISK_RATIO);
PARSE_TUNING_STR(s_hwType, NOVA_HW_TYPE);
PARSE_TUNING_X_STR(s_mqPass, RABBITMQ_OPENSTACK_PASSWD, 1);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 2);
PARSE_TUNING_X_STR(s_cubeDomain, CUBESYS_DOMAIN, 2);
PARSE_TUNING_X_STR(s_cubeRegion, CUBESYS_REGION, 2);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 2);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 2);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 2);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 2);
PARSE_TUNING_X_STR(s_neutronPass, NEUTRON_USERPASS, 3);
PARSE_TUNING_X_STR(s_metaPass, NEUTRON_METAPASS, 3);
PARSE_TUNING_X_STR(s_ironicPass, IRONIC_USERPASS, 4);

// depends on mysqld (called inside commit())
static bool
SetupCheck()
{
    if (!IsControl(s_eCubeRole))
        return true;

    if(!MysqlUtilIsDbExist("nova_api")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE nova_api") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY 'nova_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY 'nova_dbpass'")) {
            return false;
        }

        s_bSetup = false;
    }

    if(!MysqlUtilIsDbExist("nova")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE nova") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY 'nova_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY 'nova_dbpass'")) {
            return false;
        }

        s_bSetup = false;
    }

    if(!MysqlUtilIsDbExist("nova_cell0")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE nova_cell0") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY 'nova_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY 'nova_dbpass'")) {
            return false;
        }

        s_bSetup = false;
    }

    return true;
}

static bool
PlaSetupCheck()
{
    if (!IsControl(s_eCubeRole))
        return true;

    if(!MysqlUtilIsDbExist("placement")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE placement") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY 'placement_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY 'placement_dbpass'")) {
            return false;
        }

        s_bPlaSetup = false;
    }

    return true;
}

// Setup should run after keystone & nova services are running.
static bool
SetupNova(std::string domain, std::string novaPass, std::string placePass)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Setting up nova");

    // Populate the nova service database
    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"nova-manage api_db sync\" %s", USER);
    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"nova-manage cell_v2 map_cell0\" %s", USER);
    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"nova-manage cell_v2 create_cell --name=cell1 --verbose\" %s", USER);
    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"nova-manage db sync\" %s", USER);

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // Create the nova service credentials
    HexUtilSystemF(0, 0, "%s %s user create --domain %s --password %s nova",
                         env.c_str(), OSCMD, domain.c_str(), novaPass.c_str());
    HexUtilSystemF(0, 0, "%s %s role add --project service --user nova admin", env.c_str(), OSCMD);
    HexUtilSystemF(0, 0, "%s %s role add --project service --user nova service", env.c_str(), OSCMD);

    // Create the nova placement service credentials
    HexUtilSystemF(0, 0, "%s %s user create --domain %s --password %s placement",
                         env.c_str(), OSCMD, domain.c_str(), placePass.c_str());
    HexUtilSystemF(0, 0, "%s %s role add --project service --user placement admin", env.c_str(), OSCMD);

    // Create the service entity
    HexUtilSystemF(0, 0, "%s %s service create --name nova "
                         "--description \"OpenStack Compute\" compute",
                         env.c_str(), OSCMD);

    // Create the service entity
    HexUtilSystemF(0, 0, "%s %s service create --name placement "
                         "--description \"Placement API\" placement",
                         env.c_str(), OSCMD);

    // Create the nova ephemeral storage
    HexUtilSystemF(0, 0, HEX_SDK " ceph_create_pool %s rbd", VOLUME);

    return true;
}

static bool
SetupPlacement()
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Setting up placement");

    // Populate the nova service database
    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"placement-manage db sync\" %s", PLA_USER);

    return true;
}

static bool
UpdateEndpoint(std::string endpoint, std::string external, std::string region)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Updating nova endpoint");

    std::string pub = "http://" + external + ":8774/v2.1";
    std::string adm = "http://" + endpoint + ":8774/v2.1";
    std::string intr = "http://" + endpoint + ":8774/v2.1";

    HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_update %s %s %s %s %s",
                         "compute", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

    pub = "http://" + external + ":8778";
    adm = "http://" + endpoint + ":8778";
    intr = "http://" + endpoint + ":8778";

    HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_update %s %s %s %s %s",
                         "placement", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

    return true;
}

static bool
UpdateCell(std::string sharedId, std::string password)
{
    if (!IsControl(s_eCubeRole))
        return true;

    std::string dbconn = "mysql+pymysql://nova:";
    dbconn += password;
    dbconn += "@";
    dbconn += sharedId;
    dbconn += "/nova_cell0";

    HexUtilSystemF(0, 0, HEX_SDK " os_nova_cell_update %s", dbconn.c_str());
    return true;
}

static bool
UpdateDbConn(std::string sharedId, std::string password)
{
    if(IsControl(s_eCubeRole)) {
        std::string dbconn = "mysql+pymysql://nova:";
        dbconn += password;
        dbconn += "@";
        dbconn += sharedId;
        dbconn += "/nova_api";

        cfg["api_database"]["connection"] = dbconn;

        dbconn = "mysql+pymysql://nova:";
        dbconn += password;
        dbconn += "@";
        dbconn += sharedId;
        dbconn += "/nova";

        cfg["database"]["connection"] = dbconn;

        dbconn = "mysql+pymysql://placement:";
        dbconn += password;
        dbconn += "@";
        dbconn += sharedId;
        dbconn += "/placement";

        plaCfg["placement_database"]["connection"] = dbconn;
    }

    return true;
}

static bool
UpdateMqConn(const bool ha, std::string sharedId, std::string password, std::string ctrlAddrs)
{
    if (IsControl(s_eCubeRole) || IsCompute(s_eCubeRole)) {
        std::string dbconn = RabbitMqServers(ha, sharedId, password, ctrlAddrs);
        cfg["DEFAULT"]["transport_url"] = dbconn;
        cfg["DEFAULT"]["rpc_response_timeout"] = "1200";

        if (ha) {
            cfg["oslo_messaging_rabbit"]["rabbit_retry_interval"] = "1";
            cfg["oslo_messaging_rabbit"]["rabbit_retry_backoff"] = "2";
            cfg["oslo_messaging_rabbit"]["amqp_durable_queues"] = "true";
            cfg["oslo_messaging_rabbit"]["rabbit_ha_queues"] = "true";
        }
    }

    return true;
}

static bool
UpdateDebug(bool enabled)
{
    std::string value = enabled ? "true" : "false";
    cfg["DEFAULT"]["debug"] = value;

    return true;
}

static bool
UpdateControllerIp(std::string ctrlIp)
{
    if (IsControl(s_eCubeRole)) {
        cfg["DEFAULT"]["metadata_listen"] = ctrlIp;
        cfg["DEFAULT"]["osapi_compute_listen"] = ctrlIp;
        cfg["vnc"]["novncproxy_host"] = ctrlIp;
        // cfg["spice"]["html5proxy_host"] = ctrlIp;
    }

    return true;
}

static bool
UpdateSharedId(std::string sharedId)
{
    if(IsControl(s_eCubeRole) || IsCompute(s_eCubeRole)) {
        cfg["keystone_authtoken"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        cfg["keystone_authtoken"]["auth_url"] = "http://" + sharedId + ":5000";
        cfg["keystone_authtoken"]["memcached_servers"] = sharedId + ":11211";
        cfg["keystone_authtoken"]["service_token_roles"] = "service";
        cfg["keystone_authtoken"]["service_token_roles_required"] = "true";
        cfg["service_user"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        cfg["service_user"]["auth_url"] = "http://" + sharedId + ":5000";
        cfg["placement"]["auth_url"] = "http://" + sharedId + ":5000/v3";
        cfg["glance"]["api_servers"] = "http://" + sharedId + ":9292";;
        cfg["neutron"]["url"] = "http://" + sharedId + ":9696";
        cfg["neutron"]["auth_url"] = "http://" + sharedId + ":5000";
        cfg["oslo_messaging_notifications"]["transport_url"] = "kafka://" + sharedId + ":9095";

        ironicCfg["ironic"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        ironicCfg["ironic"]["auth_url"] = "http://" + sharedId + ":5000";
        ironicCfg["ironic"]["memcached_servers"] = sharedId + ":11211";

        plaCfg["keystone_authtoken"]["auth_url"] = "http://" + sharedId + ":5000/v3";
        plaCfg["keystone_authtoken"]["memcached_servers"] = sharedId + ":11211";
    }

    return true;
}

static bool
UpdateCfg(std::string domain, std::string region, std::string mcacheconn, std::string hwType,
          std::string novaPass, std::string placePass, std::string neutronPass, std::string metaPass,
          std::string external, std::string myIp, const std::string& ironicPass, const std::string& hostname)
{
    if (IsControl(s_eCubeRole)) {
        cfg["DEFAULT"]["enabled_apis"] = "osapi_compute,metadata";
        cfg["DEFAULT"]["ssl_only"] = "false";
        cfg["DEFAULT"]["cert"] = SSL_KEYFILE;
        cfg["cache"]["enabled"] = "true";
        cfg["cache"]["backend"] = "dogpile.cache.memcached";
        cfg["cache"]["memcache_servers"] = mcacheconn;
        cfg["scheduler"]["discover_hosts_in_cells_interval"] = "300";
        cfg["neutron"]["service_metadata_proxy"] = "true";
        cfg["neutron"]["metadata_proxy_shared_secret"] = metaPass.c_str();

        cfg["vnc"]["server_listen"] = myIp;
        cfg["vnc"]["server_proxyclient_address"] = myIp;

        cfg["placement"]["randomize_allocation_candidates"] = "true";
        cfg["filter_scheduler"]["host_subset_size"] = "3";
        cfg["filter_scheduler"]["shuffle_best_same_weighed_hosts"] = "true";
        cfg["filter_scheduler"]["ram_weight_multiplier"] = "5.0";
        cfg["filter_scheduler"]["enabled_filters"] = "AvailabilityZoneFilter,ComputeFilter,ComputeCapabilitiesFilter,ImagePropertiesFilter,ServerGroupAntiAffinityFilter,ServerGroupAffinityFilter,AggregateInstanceExtraSpecsFilter,PciPassthroughFilter";

        // Unset UpgradeLevelNovaCompute or live migrations fail
        // https://bugzilla.redhat.com/show_bug.cgi?id=1849235
        // cfg["upgrade_levels"]["compute"] = "auto";

        plaCfg["api"]["auth_strategy"] = "keystone";
        plaCfg["keystone_authtoken"]["auth_type"] = "password";
        plaCfg["keystone_authtoken"]["project_domain_name"] = domain.c_str();
        plaCfg["keystone_authtoken"]["user_domain_name"] = domain.c_str();
        plaCfg["keystone_authtoken"]["project_name"] = "service";
        plaCfg["keystone_authtoken"]["username"] = "placement";
        plaCfg["keystone_authtoken"]["password"] = placePass.c_str();
    }

    if (IsCompute(s_eCubeRole)) {
        cfg["vnc"]["server_listen"] = "0.0.0.0";
        cfg["vnc"]["server_proxyclient_address"] = myIp;
        // cfg["spice"]["server_listen"] = "0.0.0.0";
        // cfg["spice"]["server_proxyclient_address"] = myIp;

        cfg["vnc"]["novncproxy_base_url"] = "https://" + external + ":6080/vnc_auto.html";
        // cfg["spice"]["html5proxy_base_url"] = "http://" + external + ":6082/spice_auto.html";

        cfg["DEFAULT"]["compute_driver"] = "libvirt.LibvirtDriver";
        cfg["DEFAULT"]["state_path"] = "/var/lib/nova";
        cfg["DEFAULT"]["instances_path"] = "$state_path/instances";
        cfg["libvirt"]["hw_machine_type"] = hwType.c_str();
        cfg["libvirt"]["images_type"] = "rbd";
        cfg["libvirt"]["images_rbd_pool"] = VOLUME;
        cfg["libvirt"]["images_rbd_ceph_conf"] = "/etc/ceph/ceph.conf";
        cfg["libvirt"]["disk_cachemodes"] = "\"network=writeback\"";
        cfg["libvirt"]["inject_password"] = "false";
        cfg["libvirt"]["inject_key"] = "false";
        cfg["libvirt"]["inject_partition"] = "-2";
        cfg["libvirt"]["live_migration_flag"] = "\"VIR_MIGRATE_UNDEFINE_SOURCE,VIR_MIGRATE_PEER2PEER,VIR_MIGRATE_LIVE,VIR_MIGRATE_PERSIST_DEST,VIR_MIGRATE_TUNNELLED\"";
        cfg["libvirt"]["live_migration_scheme"] = "ssh";
        cfg["libvirt"]["hw_disk_discard"] = "unmap";
        cfg["libvirt"]["snapshot_image_format"] = "raw";
        cfg["libvirt"]["volume_use_multipath"] = "true";
        cfg["libvirt"]["live_migration_permit_post_copy"] = "true";
        std::string cpuVirtInstr = HexUtilPOpen("echo -n $(egrep -o '(vmx|svm)' /proc/cpuinfo | uniq)");
        if (cpuVirtInstr == "svm")
            cfg["libvirt"]["cpu_model_extra_flags"] = cpuVirtInstr;

        // Ceilometer
        cfg["DEFAULT"]["instance_usage_audit"] = "True";
        cfg["DEFAULT"]["instance_usage_audit_period"] = "hour";
        cfg["notifications"]["notify_on_state_change"] = "vm_and_task_state";

        std::string gpuType = HexUtilPOpen(HEX_SDK " gpu_default_type_get");
        if (gpuType.length())
            cfg["devices"]["enabled_vgpu_types"] = gpuType;
        if (s_gpuType.length())
            cfg["devices"]["enabled_vgpu_types"] = s_gpuType.newValue();

        ironicCfg["DEFAULT"]["host"] = hostname + "-ironic";
        ironicCfg["DEFAULT"]["compute_driver"] = "ironic.IronicDriver";
        ironicCfg["DEFAULT"]["reserved_host_cpus"] = "0";
        ironicCfg["DEFAULT"]["reserved_host_memory_mb"] = "0";
        ironicCfg["filter_scheduler"]["track_instance_changes"] = "false";
        ironicCfg["scheduler"]["discover_hosts_in_cells_interval"] = "120";

        ironicCfg["ironic"]["auth_type"] = "password";
        ironicCfg["ironic"]["project_domain_name"] = domain.c_str();
        ironicCfg["ironic"]["user_domain_name"] = domain.c_str();
        ironicCfg["ironic"]["project_name"] = "service";
        ironicCfg["ironic"]["username"] = "ironic";
        ironicCfg["ironic"]["password"] = ironicPass.c_str();
    }

    if(IsControl(s_eCubeRole) || IsCompute(s_eCubeRole)) {
        cfg["DEFAULT"]["my_ip"] = myIp;
        cfg["DEFAULT"]["resume_guests_state_on_host_boot"] = "true";
        cfg["DEFAULT"]["block_device_allocate_retries"] = "300";
        cfg["DEFAULT"]["allow_resize_to_same_host"] = "true";
        cfg["DEFAULT"]["log_dir"] = "/var/log/nova";
        cfg["DEFAULT"]["host"] = hostname;

        cfg["DEFAULT"]["vnc_enabled"] = "true";
        cfg["DEFAULT"]["cpu_allocation_ratio"] = s_ocCpuRatio.newValue();
        cfg["DEFAULT"]["ram_allocation_ratio"] = s_ocRamRatio.newValue();
        cfg["DEFAULT"]["disk_allocation_ratio"] = s_ocDiskRatio.newValue();
        cfg["vnc"]["enabled"] = "true";

        // cfg["spice"]["enabled"] = "true";
        // cfg["spice"]["agent_enabled"] = "true";

        cfg["oslo_concurrency"]["lock_path"] = "/var/lib/nova/tmp";

        cfg["api"]["auth_strategy"] = "keystone";
        cfg["api"]["list_records_by_skipping_down_cells"] = "false";

        cfg["keystone_authtoken"]["auth_type"] = "password";
        cfg["keystone_authtoken"]["project_domain_name"] = domain.c_str();
        cfg["keystone_authtoken"]["user_domain_name"] = domain.c_str();
        cfg["keystone_authtoken"]["project_name"] = "service";
        cfg["keystone_authtoken"]["username"] = "nova";
        cfg["keystone_authtoken"]["password"] = novaPass.c_str();

        cfg["placement"]["os_region_name"] = region.c_str();
        cfg["placement"]["project_domain_name"] = domain.c_str();
        cfg["placement"]["user_domain_name"] = domain.c_str();
        cfg["placement"]["project_name"] = "service";
        cfg["placement"]["auth_type"] = "password";
        cfg["placement"]["username"] = "placement";
        cfg["placement"]["password"] = placePass.c_str();

        // Neutron
        cfg["neutron"]["auth_type"] = "password";
        cfg["neutron"]["project_domain_name"] = domain.c_str();
        cfg["neutron"]["user_domain_name"] = domain.c_str();
        cfg["neutron"]["project_name"] = "service";
        cfg["neutron"]["username"] = "neutron";
        cfg["neutron"]["password"] = neutronPass.c_str();
        cfg["neutron"]["region_name"] = region.c_str();

        // Cinder
        cfg["cinder"]["os_region_name"] = region.c_str();

        cfg["oslo_messaging_notifications"]["driver"] = "messagingv2";

        cfg["service_user"]["send_service_user_token"] = "true";
        cfg["service_user"]["auth_type"] = "password";
        cfg["service_user"]["project_domain_name"] = domain.c_str();
        cfg["service_user"]["user_domain_name"] = domain.c_str();
        cfg["service_user"]["project_name"] = "service";
        cfg["service_user"]["username"] = "nova";
        cfg["service_user"]["password"] = novaPass.c_str();

    }


#define MIN(x, y) (x < y ? x : y)
    if (IsConverged(s_eCubeRole) || IsCore(s_eCubeRole) || IsCompute(s_eCubeRole)) {
        uint64_t ctrlMem = ControlMemoryReservedMib;
        if (IsCore(s_eCubeRole)) {
            ctrlMem = ctrlMem / 2;
        }
        uint64_t reservedHci = std::stoul(HexUtilPOpen(HEX_SDK " os_nova_hci_reserved_mem_mb"));
        uint64_t mem = s_resvHostMem.newValue() + ctrlMem + reservedHci;

        struct sysinfo info;
        if (sysinfo(&info) == 0)
            mem = MIN(info.totalram >> 21 /* 20 (megabyte) + 1 (half system mem) */, mem);

        cfg["DEFAULT"]["reserved_host_memory_mb"] = std::to_string(mem);

        if (IsConverged(s_eCubeRole) || IsCore(s_eCubeRole)) {
            uint64_t ctrlCpu = ControlVcpuReserved;
            uint64_t vcpus = s_resvHostVcpu.newValue() + ctrlCpu;
            unsigned int totalCpus = std::thread::hardware_concurrency();

            vcpus = MIN(totalCpus / 2, vcpus);
            cfg["DEFAULT"]["reserved_host_cpus"] = std::to_string(vcpus);
        }
    }
#undef MIN

    if (IsControl(s_eCubeRole)) {
        std::string workers = std::to_string(GetControlWorkers(IsConverged(s_eCubeRole), IsEdge(s_eCubeRole)));
        cfg["DEFAULT"]["osapi_compute_workers"] = workers;
        cfg["DEFAULT"]["metadata_workers"] = workers;
        cfg["conductor"]["workers"] = workers;
        cfg["scheduler"]["workers"] = workers;
    }

    return true;
}

static bool
NovaService(bool enabled)
{
    if (IsControl(s_eCubeRole)) {
        SystemdCommitService(enabled, CNTR_NAME, true);    // nova-conductor
        SystemdCommitService(enabled, SCHL_NAME, true);    // nova-scheduler
        SystemdCommitService(enabled, VNCP_NAME, true);    // nova-novncproxy
        SystemdCommitService(enabled, API_NAME, true);     // nova-api
        // SystemdCommitService(enabled, SPICEP_NAME, true);   // nova-spicehtml5proxy
    }

    if (IsCompute(s_eCubeRole)) {
        SystemdCommitService(enabled, CMP_NAME, true);
        SystemdCommitService(enabled, MULTIPATHD, true);
        SystemdCommitService(enabled, ISCSI_NAME, true);   // nova-compute complains not finding /etc/iscsi/initiatorname.iscsi
        //SystemdCommitService(enabled, QEMU_GA, true);
    }

    return true;
}

static bool
Init()
{
    if (HexMakeDir(RUNDIR, USER, GROUP, 0755) != 0 ||
        HexMakeDir(CERTDIR, USER, GROUP, 0755) != 0 ||
        HexMakeDir(NOVA_SSH, USER, GROUP, 0755) != 0 ||
        HexMakeDir(NOVA_CEPH_LOG, "qemu", "qemu", 0755) != 0)
        return false;

    if (access(MULTIPATH_CONF, F_OK) != 0) {
        HexUtilSystemF(0, 0, "mpathconf --enable");
    }

    // load nova configurations
    if (!LoadConfig(CONF DEF_EXT, SB_SEC_RFMT, '=', cfg)) {
        HexLogError("failed to load nova config file %s", CONF);
        return false;
    }

    if (!LoadConfig(PLA_CONF DEF_EXT, SB_SEC_RFMT, '=', plaCfg)) {
        HexLogError("failed to load placement config file %s", PLA_CONF);
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
    if (strcmp(name, NET_HOSTNAME) == 0) {
        s_hostname.parse(value, isNew);
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
ParseNeutron(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 3);
    return true;
}

static bool
ParseIronic(const char *name, const char *value, bool isNew)
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
NotifyNeutron(bool modified)
{
    s_bNeutronModified = IsModifiedTune(3);
}

static void
NotifyIronic(bool modified)
{
    s_bIronicModified = IsModifiedTune(4);
}

static bool
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        s_bConfigChanged = true;
        HexUtilSystemF(0, 0, HEX_SDK " os_nova_mdev_instance_sync");
        return true;
    }

    s_bDbPassChanged = s_dbPass.modified() | s_bCubeModified;

    s_bConfigChanged = modified | s_bNetModified | s_bMqModified |
                s_bCubeModified | s_bNeutronModified | s_bIronicModified |
               G_MOD(MGMT_ADDR) | G_MOD(CTRL_IP) | G_MOD(SHARED_ID);

    s_bEndpointChanged = s_bCubeModified | G_MOD(SHARED_ID) | G_MOD(EXTERNAL);

    s_bCellChanged = s_dbPass.modified() | s_mqPass.modified() | s_bCubeModified | G_MOD(SHARED_ID);

    return s_bDbPassChanged | s_bConfigChanged | s_bEndpointChanged | s_bCellChanged;
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    std::string myIp = G(MGMT_ADDR);
    std::string ctrlIp = G(CTRL_IP);
    std::string sharedId = G(SHARED_ID);
    std::string external = G(EXTERNAL);

    std::string novaPass = GetSaltKey(s_saltkey, s_novaPass.newValue(), s_seed.newValue());
    std::string placePass = GetSaltKey(s_saltkey, s_placePass.newValue(), s_seed.newValue());
    std::string neutronPass = GetSaltKey(s_saltkey, s_neutronPass.newValue(), s_seed.newValue());
    std::string metaPass = GetSaltKey(s_saltkey, s_metaPass.newValue(), s_seed.newValue());
    std::string ironicPass = GetSaltKey(s_saltkey, s_ironicPass.newValue(), s_seed.newValue());
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass.newValue(), s_seed.newValue());
    std::string plaBbPass = GetSaltKey(s_saltkey, s_plaDbPass.newValue(), s_seed.newValue());
    std::string mqPass = GetSaltKey(s_saltkey, s_mqPass.newValue(), s_seed.newValue());
    // this setting is controller only
    std::string mcacheconn = MemcachedServers(s_ha, ctrlIp, s_ctrlAddrs.newValue());

    if (access(SSL_KEYFILE, F_OK) != 0 && access(SSL_KEYFILE_SRC, F_OK) == 0) {
        HexUtilSystemF(0, 0, "cp -f %s %s", SSL_KEYFILE_SRC, SSL_KEYFILE);
        HexUtilSystemF(0, 0, "chown nova:nova %s", SSL_KEYFILE);
        HexUtilSystemF(0, 0, "chmod 600 %s", SSL_KEYFILE);
    }

    if(access(NOVA_SSH_KEY, F_OK) != 0) {
        HexUtilSystemF(0, 0, HEX_SDK " os_nova_sshkey_create %s", NOVA_SSH);
    }

    SetupCheck();
    if (!s_bSetup) {
        s_bDbPassChanged = true;
        s_bEndpointChanged = true;
    }

    PlaSetupCheck();
    if (!s_bPlaSetup) {
        s_bPlaDbPassChanged = true;
    }

    if (s_bDbPassChanged && IsControl(s_eCubeRole))
        MysqlUtilUpdateDbPass(USER, dbPass.c_str());

    if (s_bPlaDbPassChanged && IsControl(s_eCubeRole))
        MysqlUtilUpdateDbPass(PLA_USER, plaBbPass.c_str());

    // 2. Service Config
    if (s_bConfigChanged) {
        UpdateCfg(s_cubeDomain.newValue(), s_cubeRegion.newValue(), mcacheconn, s_hwType.newValue(),
                  novaPass, placePass, neutronPass, metaPass, external, myIp, ironicPass, s_hostname);
        UpdateSharedId(sharedId);
        UpdateControllerIp(ctrlIp);
        UpdateDbConn(sharedId, dbPass);
        UpdateMqConn(s_ha, sharedId, mqPass, s_ctrlAddrs.newValue());
        UpdateDebug(s_debug.newValue());

        // write back to nova config files
        WriteConfig(CONF, SB_SEC_WFMT, '=', cfg);
        WriteConfig(PLA_CONF, SB_SEC_WFMT, '=', plaCfg);
        WriteConfig(IRONIC_CONF, SB_SEC_WFMT, '=', ironicCfg);
        HexSetFileMode(PLA_CONF, PLA_USER, PLA_USER, 0644);
    }

    // 3. Service Setup (service must be running)
    if (!s_bSetup)
        SetupNova(s_cubeDomain.newValue(), novaPass, placePass);

    // check for db migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_nova_db");

    if (!s_bPlaSetup)
        SetupPlacement();

    if (s_bEndpointChanged) {
        UpdateEndpoint(sharedId, external, s_cubeRegion.newValue());
    }

    if (s_bCellChanged) {
        UpdateCell(sharedId, dbPass);
    }

    // 4. Service kickoff
    NovaService(s_enabled);

    return true;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_nova\n", HexLogProgramName());
}

static int
RestartMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartUsage();
        return EXIT_FAILURE;
    }

    NovaService(s_enabled);

    return EXIT_SUCCESS;
}

static int
ClusterStartMain(int argc, char **argv)
{
    if (argc != 1) {
        return EXIT_FAILURE;
    }

    // post actions for db migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_nova_db_post");

    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(restart_nova, RestartMain, RestartUsage);

CONFIG_MODULE(nova, Init, Parse, 0, 0, Commit);
// startup sequence
CONFIG_REQUIRES(nova, libvirtd);
CONFIG_REQUIRES(nova, memcache);
//CONFIG_REQUIRES(nova, glance);

CONFIG_MIGRATE(nova, "/etc/nova/nova.d");

// extra tunings
CONFIG_OBSERVES(nova, net, ParseNet, NotifyNet);
CONFIG_OBSERVES(nova, rabbitmq, ParseRabbitMQ, NotifyMQ);
CONFIG_OBSERVES(nova, cubesys, ParseCube, NotifyCube);
CONFIG_OBSERVES(nova, neutron, ParseNeutron, NotifyNeutron);
CONFIG_OBSERVES(nova, ironic, ParseIronic, NotifyIronic);

CONFIG_TRIGGER_WITH_SETTINGS(nova, "cluster_start", ClusterStartMain);

