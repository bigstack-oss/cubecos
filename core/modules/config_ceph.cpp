// CUBE

#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/stat.h>

#include <list>
#include <cctype>
#include <iterator>

#include <hex/log.h>
#include <hex/pidfile.h>
#include <hex/filesystem.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/string_util.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>

#include <cube/network.h>
#include <cube/cluster.h>
#include <cube/systemd_util.h>

#include "include/role_cubesys.h"

#define MONDIR_FMT "/var/lib/ceph/mon/ceph-%s"
#define MGRDIR_FMT "/var/lib/ceph/mgr/ceph-%s"
#define MDSDIR_FMT "/var/lib/ceph/mds/ceph-%s"
#define OSDDIR_FMT "/var/lib/ceph/osd/ceph-%lu"
#define RGWDIR_FMT "/var/lib/ceph/radosgw/ceph-radosgw.%s"
#define MAKRER_FMT "/var/lib/ceph/mon/ceph-%s/done"
#define MIRROR_CONF_FMT "/etc/ceph/%s-site.conf"
#define MIRROR_CONF_WILDCARD "/etc/ceph/*-site.conf"

#define MAKRER_POOL "/etc/appliance/state/ceph_osd_pool_done"
#define MAKRER_CEPHFS "/etc/appliance/state/cephfs_done"
#define MAKRER_RESTFUL "/etc/appliance/state/ceph_restful_done"
#define MAKRER_AUTOSCALE "/etc/appliance/state/ceph_autoscale_done"
#define MAKRER_MSGR2 "/etc/appliance/state/ceph_msgr2_done"
#define MAKRER_CLIENT "/etc/appliance/state/ceph_client_done"
#define MAKRER_DASHBOARD "/etc/appliance/state/ceph_dashboard_done"
#define MAKRER_DASHBOARD_IDP "/etc/appliance/state/ceph_dashboard_idp_done"
#define MAKRER_ISCSI "/etc/appliance/state/ceph_iscsi_done"
#define MAKRER_ISCSIGW "/etc/appliance/state/ceph_iscsi_gw_done"

#define DASHBOARD_PORT "7443"
#define DASHBOARD_HA_PORT "7442"
#define RESTFUL_PORT "8003"
#define ISCSI_API_PORT "5010"

const static char NAME[] = "ceph";
const static char USER[] = "ceph";
const static char GROUP[] = "ceph";
const static char CONF[] = "/etc/ceph/ceph.conf";
const static char ISCSI_GW_CONF[] = "/etc/ceph/iscsi-gateway.cfg";
const static char NFS_GANESHA_CONF[] = "/etc/ganesha/ganesha.conf";
const static char CONF_DEF[] = "/etc/default/ceph";
const static char APP_DIR[] = "/var/lib/ceph";
const static char CLIENT_SOCK[] = "/var/run/ceph/guests/";
// /usr/lib/python2.7/dist-packages/os_brick/initiator/connectors/rbd.py
// requires the presence of the keyring file
const static char KEYRING_DIR[] = "/etc/ceph";
const static char KEYRING_FILE[] = "/etc/ceph/ceph.keyring";
const static char DUMMY_KEYRING[] = "/etc/ceph/ceph.client.None.keyring";
const static char ADMIN_KEYRING[] = "/etc/ceph/ceph.client.admin.keyring";
const static char K8S_KEYRING[] = "/etc/ceph/ceph.client.k8s.keyring";
const static char CEPHFS_CLIENT_AUTHKEY[] = "/etc/ceph/admin.key";

static const char FSID[] = "c6e64c49-09cf-463b-9d1c-b6645b4b3b85";

static const char CEPH_CACHE_POOL[] = "cachepool";
static const char K8S_VOLUME[] = "k8s-volumes";
static const char CINDER_VOLUME[] = "cinder-volumes";
static const char EPHEMERAL_VOLUME[] = "ephemeral-vms";

static const char CEPHFS_DATA_POOL[] = "cephfs_data";
static const char CEPHFS_METADATA_POOL[] = "cephfs_metadata";
static const char CEPHFS_NAME[] = "cephfs";
static const char CEPHFS_DEFAULT_SUB_VOLUME_GROUP[] = "cephfs_default_sub_volume_group";
static const char CEPHFS_STORE_DIR[] = "/mnt/cephfs";

static const char SRV_KEY[] = "/var/www/certs/server.key";
static const char SRV_CRT[] = "/var/www/certs/server.cert";

static const char GWAPIPASS[] = "Xv67nUJYFL5kravv";

static bool s_bNetModified = false;
static bool s_bCubeModified = false;
static bool s_bKeystoneModified = false;

static bool s_bRbdMirrorChanged = false;
static bool s_bMonMapChanged = false;
static bool s_bConfigChanged = false;

static ConfigString s_hostname;
static CubeRole_e s_eCubeRole;
static std::list<size_t> s_osdIds;
static std::list<size_t> s_osdNewIds; // newly added osd Id

// external global variables
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_BOOL_REF(IS_MASTER);
CONFIG_GLOBAL_STR_REF(CTRL);
CONFIG_GLOBAL_STR_REF(CTRL_IP);
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(STORAGE_F_ADDR);
CONFIG_GLOBAL_STR_REF(STORAGE_F_CIDR);
CONFIG_GLOBAL_STR_REF(STORAGE_B_CIDR);

// public tunings
CONFIG_TUNING_BOOL(CEPH_DEBUG_ENABLED, "ceph.debug.enabled", TUNING_PUB, "Set to true to enable ceph debug logs.", false);
CONFIG_TUNING_BOOL(CEPH_MIRROR_META_SYNC, "ceph.mirror.meta.sync", TUNING_PUB, "Set to true to enable automatically volume metadata sync.", true);

// private tunings
CONFIG_TUNING_BOOL(CEPH_ENABLED, "ceph.enabled", TUNING_UNPUB, "Set to true to enable ceph service.", true);
CONFIG_TUNING_BOOL(CEPH_MON_ENABLED, "ceph.mon.enabled", TUNING_UNPUB, "Enable ceph monitor on this host.", false);
CONFIG_TUNING_BOOL(CEPH_PERF_TUNED, "ceph.perf.tuned", TUNING_UNPUB, "Enable ceph performance tuning on this host.", true);
CONFIG_TUNING_STR(CEPH_FSID, "ceph.fsid", TUNING_UNPUB, "Set to true to enable ceph service.", FSID, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_BOOL(CEPH_MIRROR_ENABLED, "ceph.mirror.enabled", TUNING_UNPUB, "Enable ceph rbd mirror.", false);
CONFIG_TUNING_STR(CEPH_MIRROR_NAME, "ceph.mirror.name", TUNING_UNPUB, "Set local site name.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CEPH_MIRROR_PEER_NAME, "ceph.mirror.peer.%d.name", TUNING_UNPUB, "Set peer site name.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CEPH_MIRROR_PEER_IP, "ceph.mirror.peer.%d.ipaddr", TUNING_UNPUB, "Set peer IP address.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CEPH_MIRROR_PEER_SECRET, "ceph.mirror.peer.%d.secret", TUNING_UNPUB, "Set peer secret (root account password).", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CEPH_MIRROR_RULE_VOLUME, "ceph.mirror.rule.%d.volume", TUNING_UNPUB, "Set mirrored volume.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CEPH_GWAPIPASS, "ceph.iscsi.gwapi.password", TUNING_UNPUB, "Set iSCSI Gateway API password.", GWAPIPASS, ValidateRegex, DFT_REGEX_STR);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_HOSTS);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_STR(KEYSTONE_ADMIN_CLI_PASS);

// parse tunings
PARSE_TUNING_BOOL(s_debugEnabled, CEPH_DEBUG_ENABLED);
PARSE_TUNING_BOOL(s_enabled, CEPH_ENABLED);
PARSE_TUNING_STR(s_fsid, CEPH_FSID);
PARSE_TUNING_BOOL(s_mirrorEnabled, CEPH_MIRROR_ENABLED);
PARSE_TUNING_BOOL(s_monEnabled, CEPH_MON_ENABLED);
PARSE_TUNING_BOOL(s_perfTuned, CEPH_PERF_TUNED);
PARSE_TUNING_STR(s_mirrorName, CEPH_MIRROR_NAME);
PARSE_TUNING_BOOL(s_mirrorMetaSync, CEPH_MIRROR_META_SYNC);
PARSE_TUNING_STR_ARRAY(s_peerNameAry, CEPH_MIRROR_PEER_NAME);
PARSE_TUNING_STR_ARRAY(s_peerIpAry, CEPH_MIRROR_PEER_IP);
PARSE_TUNING_STR_ARRAY(s_peerSecretAry, CEPH_MIRROR_PEER_SECRET);
PARSE_TUNING_STR_ARRAY(s_ruleVolumeAry, CEPH_MIRROR_RULE_VOLUME);
PARSE_TUNING_STR(s_gwApiPass, CEPH_GWAPIPASS);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_ctrlHosts, CUBESYS_CONTROL_HOSTS, 1);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 1);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 1);

// FIXME: circular issue
//PARSE_TUNING_X_STR(s_adminCliPass, KEYSTONE_ADMIN_CLI_PASS, 2);
static ConfigString s_adminCliPass("66K1ogIiRt5KnyHe");

static bool
__setup_bluestore()
{
    // 1. Partition/format all prepared osd disks
    std::string prep_devs = HexUtilPOpen(HEX_SDK " ListPreparedDisks");
    if (prep_devs.length() >= 8 /* start with /dev/sdx | /dev/nvme0n1 */) {
        std::vector<std::string> devs = hex_string_util::split(prep_devs, ' ');
        for (auto& d : devs) {
            if (d.length() == 0)
                continue;

            int part_nums = 2;
            int part_size = 819200;  // sectors (512B) --> 400 MB by default
            std::string type = "scsi";

            std::size_t found = d.find("nvme");
            if (found != std::string::npos) {
                type = "nvme";
                part_nums = 2;
            }

            HexUtilSystemF(0, 0, HEX_SDK " ceph_osd_prepare_bluestore %s %d %d %s",
                           d.c_str(), part_nums, part_size, type.c_str());
        }
    }

    // 2. Bring up osds (old and new)
    HexUtilSystemF(0, 0, HEX_SDK " ceph_osd_relabel");
    std::string osd_devs = HexUtilPOpen(HEX_SDK " ceph_osd_list_meta_partitions");
    if (osd_devs.length() < 8 /* start with /dev/sdx */)
        return true;
    std::vector<std::string> devs = hex_string_util::split(osd_devs, ' ');
    for (auto& d : devs) {
        if (d.length() == 0)
            continue;

        std::string dataPart = HexUtilPOpen(HEX_SDK " ceph_osd_get_datapart %s", d.c_str());
        HexSystemF(0, "chown %s:%s %s", USER, GROUP, d.c_str());
        HexSystemF(0, "chown %s:%s %s", USER, GROUP, dataPart.c_str());

        char osddir[256];
        size_t osdId = 0;
        struct stat ds;
        std::string uuid = HexUtilPOpen(HEX_SDK " GetBlkUuid %s", d.c_str());
        std::string strOsdId = HexUtilPOpen(HEX_SDK " ceph_osd_get_id %s", d.c_str());
        if (!HexParseUInt(strOsdId.c_str(), 0, UINT_MAX, &osdId)) {
            HexLogError("failed to parse outputs of ceph_osd_get_id %s: \"%s\"", d.c_str(), strOsdId.c_str());
            return false;
        }
        snprintf(osddir, sizeof(osddir), OSDDIR_FMT, osdId);
        s_osdIds.push_back(osdId);

        if (stat(osddir, &ds) == 0 && S_ISDIR(ds.st_mode))
            HexUtilSystemF(0, 0, "mount %s %s", d.c_str(), osddir);
        else {
            if (HexMakeDir(osddir, USER, GROUP, 0755) != 0) {
                HexLogError("failed to create ceph osd directory %s", osddir);
                return false;
            }
            s_osdNewIds.push_back(osdId);
            std::string dataPartUuid = HexUtilPOpen(HEX_SDK " ceph_osd_get_datapartuuid %s", d.c_str());
            HexSystemF(0, "mount %s %s", d.c_str(), osddir);
            HexSystemF(0, "rm -rf %s/*", osddir);
            HexSystemF(0, "echo bluestore > %s/type", osddir);
            HexSystemF(0, "ln -sf /dev/disk/by-partuuid/%s %s/block", dataPartUuid.c_str(), osddir);
            HexUtilSystemF(0, 0, "ceph-osd -i %lu --mkfs --osd-uuid %s >/dev/null 2>&1", osdId, uuid.c_str());
            HexSystemF(0, "chown -R %s:%s %s", USER, GROUP, osddir);
        }
    }
    HexSystemF(0, "ceph-volume lvm activate --all >/dev/null 2>&1");

    return true;
}

static bool
IsMonEnabled(bool ha, bool monEn, CubeRole_e role, const std::string& ctrlHosts)
{
    // by default either running ceph monitor only on control master node,
    // or controller cluster size > 3 which can support quorum naturally
    bool enabled = monEn | G(IS_MASTER) | (IsControl(role) && (GetClusterSize(ha, ctrlHosts) >= 3));

    return enabled;
}

static bool
SetupMon(bool enabled, std::string hostname, std::string fsid,
         const char* storIp, const bool isMaster)
{
    if (!enabled)
        return true;

    char mondir[256], marker[256];
    struct stat ds, ms;

    snprintf(mondir, sizeof(mondir), MONDIR_FMT, hostname.c_str());
    snprintf(marker, sizeof(marker), MAKRER_FMT, hostname.c_str());
    if (stat(mondir, &ds) == 0 && S_ISDIR(ds.st_mode) && stat(marker, &ms) == 0)
        return true;

    if (HexMakeDir(mondir, USER, GROUP, 0755) != 0) {
        HexLogError("failed to create ceph mon directory %s", mondir);
        return false;
    }

    if (isMaster && access(CONTROL_REJOIN, F_OK) != 0)
        HexUtilSystemF(0, 0, "sudo -u %s monmaptool --create --add %s %s "
                             "--fsid %s /tmp/monmap --clobber",
                             USER, hostname.c_str(), storIp, fsid.c_str());
    else
        HexUtilSystemF(0, 0, "sudo -u %s timeout 10 ceph mon getmap -o /tmp/monmap", USER);

    HexUtilSystemF(0, 0, "sudo -u %s ceph-mon --mkfs -i %s --monmap /tmp/monmap",
                         USER, hostname.c_str());
    HexSystemF(0, "touch %s", marker);

    return true;
}

static bool
SetupMgr(std::string hostname)
{
    if (!IsControl(s_eCubeRole))
        return true;

    char mgrdir[256];

    snprintf(mgrdir, sizeof(mgrdir), MGRDIR_FMT, hostname.c_str());
    if (HexMakeDir(mgrdir, USER, GROUP, 0755) != 0) {
        HexLogError("failed to create ceph mgr directory %s", mgrdir);
        return false;
    }

    return true;
}

static bool
SetupMds(std::string hostname)
{
    if (!IsControl(s_eCubeRole))
        return true;

    char mdsdir[256];
    std::string myIp = G(MGMT_ADDR);

    snprintf(mdsdir, sizeof(mdsdir), MDSDIR_FMT, hostname.c_str());
    if (HexMakeDir(mdsdir, USER, GROUP, 0755) != 0) {
        HexLogError("failed to create ceph mds directory %s", mdsdir);
        return false;
    }
    if (HexSystemF(0, "sed -i 's/@BIND_ADDR@/%s/' %s", myIp.c_str(), NFS_GANESHA_CONF) != 0) {
      HexLogError("failed to update %s", NFS_GANESHA_CONF);
      return false;
    }

    return true;
}

static bool
SetupOsd(std::string hostname, std::string fsid)
{
    s_osdIds.clear();
    s_osdNewIds.clear();

    __setup_bluestore();
    HexUtilSystemF(0, 0, HEX_SDK " ceph_osd_create_map");
    HexUtilSystemF(0, 0, HEX_SDK " ceph_osd_remount");

    return true;
}

static bool
SetupRgw(std::string hostname)
{
    char rgwdir[256], nssdir[256];

    if (!IsControl(s_eCubeRole))
        return true;

    snprintf(rgwdir, sizeof(rgwdir), RGWDIR_FMT, hostname.c_str());
    snprintf(nssdir, sizeof(nssdir), RGWDIR_FMT "/nss", hostname.c_str());
    if (HexMakeDir(rgwdir, USER, GROUP, 0755) != 0 ||
        HexMakeDir(nssdir, USER, GROUP, 0755) != 0) {
        HexLogError("failed to create ceph rgw directory %s", rgwdir);
        return false;
    }

    return true;
}

static bool
SetupRbdMirror(const bool enabled, const bool sync,
               const TuningStringArray& peerIpAry,
               const TuningStringArray& peerSecretAry,
               const TuningStringArray& peerNameAry,
               const TuningStringArray& ruleVolumeAry)
{
    if (enabled) {
        HexUtilSystemF(0, 0, "rbd mirror pool enable glance-images image");
        HexUtilSystemF(0, 0, "rbd mirror pool enable cinder-volumes image");

        for (unsigned i = 1 ; i < peerNameAry.size() ; i++) {
            std::string siteName = peerNameAry.newValue(i);
            HexUtilSystemF(0, 0, HEX_SDK " ceph_mirror_pool_peer_set glance-images %s-site", siteName.c_str());
            HexUtilSystemF(0, 0, HEX_SDK " ceph_mirror_pool_peer_set cinder-volumes %s-site", siteName.c_str());
        }

        std::string imglist = "";

        for (unsigned i = 1 ; i < ruleVolumeAry.size() ; i++) {
            std::string imageId = ruleVolumeAry.newValue(i);
            if (imageId.length() < 36 /* uuid length */)
                continue;

            imglist += imageId + ",";
            HexUtilSystemF(0, 0, HEX_SDK " ceph_mirror_image_enable %s", imageId.c_str());
            if (sync) {
                for (unsigned i = 1 ; i < peerNameAry.size() ; i++) {
                    std::string siteIp = peerIpAry.newValue(i);
                    std::string secret = peerSecretAry.newValue(i);
                    HexUtilSystemF(0, 0, HEX_SDK " os_volume_meta_sync %s %s %s",
                                         siteIp.c_str(), secret.c_str(), imageId.c_str());
                }
            }
        }

        HexUtilSystemF(0, 0, HEX_SDK " ceph_mirror_image_state_sync \"%s\"", imglist.c_str());
    }
    else {
        if (!IsBootstrap())
            HexUtilSystemF(0, 0, HEX_SDK " ceph_mirror_disable");
    }

    return true;
}

static bool SetupPools()
{
    struct stat ms;
    if (stat(MAKRER_POOL, &ms) == 0)
        return true;

    std::vector<std::string> pools;
    pools.push_back(".rgw.root");
    pools.push_back("default.rgw.control");
    pools.push_back("default.rgw.data.root");
    pools.push_back("default.rgw.gc");
    pools.push_back("default.rgw.log");
    pools.push_back("default.rgw.intent-log");
    pools.push_back("default.rgw.meta");
    pools.push_back("default.rgw.usage");
    pools.push_back("default.rgw.users.keys");
    pools.push_back("default.rgw.users.email");
    pools.push_back("default.rgw.users.swift");
    pools.push_back("default.rgw.users.uid");
    pools.push_back("default.rgw.buckets.extra");
    pools.push_back("default.rgw.buckets.index");
    pools.push_back("default.rgw.buckets.data");

    HexSystemF(0, "for i in 1 2 3 4 5 ; do ! timeout 60 ceph -s > /dev/null || break ; done");
    for (auto& p : pools) {
        HexUtilSystemF(0, 0, HEX_SDK " ceph_create_pool %s rgw", p.c_str());
    }

    HexUtilSystemF(0, 0, HEX_SDK " ceph_create_pool %s rbd", CEPH_CACHE_POOL);
    HexUtilSystemF(0, 0, HEX_SDK " ceph_create_pool %s rbd", K8S_VOLUME);

    HexSystemF(0, "touch " MAKRER_POOL);

    return true;
}

static bool
SetupFS()
{
    if (!IsControl(s_eCubeRole))
        return true;

    // NOTE: dont use "ceph" command in case quorum is not ready
    // Assure the presence of cephfs pools
    if (access(MAKRER_CEPHFS, F_OK) != 0) {
        // Current kernel verion 4.4 doesn't support CRUSH_TUNABLES5
        // Remove it after upgrading kernel version above 4.5
        //HexUtilSystemF(0, 0, "ceph osd crush tunables hammer");

        // Create ceph pools for data and metadata
        HexUtilSystemF(0, 0, HEX_SDK " ceph_create_pool %s cephfs", CEPHFS_DATA_POOL);
        HexUtilSystemF(0, 0, HEX_SDK " ceph_create_pool %s cephfs", CEPHFS_METADATA_POOL);

        // Create ceph filesystem
        HexUtilSystemF(0, 0, "timeout 10 ceph fs new %s %s %s", CEPHFS_NAME, CEPHFS_METADATA_POOL, CEPHFS_DATA_POOL);
        // Enable snapshot in Ceph backend to support manila share snapshot
        HexUtilSystemF(0, 0, "timeout 10 ceph fs set %s allow_new_snaps true", CEPHFS_NAME);

        HexSystemF(0, "touch " MAKRER_CEPHFS);
    }

    return true;
}

static bool SetupISCSI()
{
    struct stat ms;
    if (stat(MAKRER_ISCSI, &ms) == 0)
        return true;

    HexUtilSystemF(0, 0, HEX_SDK " ceph_create_pool rbd rbd %d", s_ha ? 3 : 1);

    HexSystemF(0, "touch " MAKRER_ISCSI);

    return true;
}

static bool
UpdateISCSIConfig(const std::string& iplist, const std::string& gwApiPass)
{
    FILE *fout = fopen(ISCSI_GW_CONF, "w");
    if (!fout) {
        HexLogError("Unable to write %s iscsi config: %s", NAME, CONF);
        return false;
    }

    fprintf(fout, "[config]\n");
    fprintf(fout, "cluster_name = ceph\n");
    fprintf(fout, "gateway_keyring = ceph.client.admin.keyring\n");
    fprintf(fout, "api_secure = false\n");
    fprintf(fout, "api_user = admin\n");
    fprintf(fout, "api_password = %s\n", gwApiPass.c_str());
    fprintf(fout, "api_port = " ISCSI_API_PORT "\n");
    fprintf(fout, "trusted_ip_list = %s\n", iplist.c_str());
    fprintf(fout, "minimum_gateways = 1\n");

    fclose(fout);

    return true;
}

static bool
UpdateConfig(std::string fsid, std::string hostname,
             std::string myip, std::string sharedId,
             std::string monHosts, std::string monIplist,
             std::string pubNet, std::string clstrNet,
             std::string adminCliPass, bool perfTuned, std::string mdsIplist="")
{
    FILE *fout = fopen(CONF, "w");
    if (!fout) {
        HexLogError("Unable to write %s config: %s", NAME, CONF);
        return false;
    }

    fprintf(fout, "[global]\n");
    fprintf(fout, "fsid = %s\n", fsid.c_str());
    fprintf(fout, "mon initial members = %s\n", monHosts.c_str());
    fprintf(fout, "mon host = %s\n", monIplist.c_str());
    fprintf(fout, "public network = %s\n", pubNet.c_str());
    fprintf(fout, "cluster network = %s\n", clstrNet.c_str());
    fprintf(fout, "auth cluster required = none\n");
    fprintf(fout, "auth service required = none\n");
    fprintf(fout, "auth client required = none\n");
    fprintf(fout, "auth allow insecure global id reclaim = false\n");
    fprintf(fout, "mon max pg per osd = 4096\n");
    fprintf(fout, "mon osd max split count = 4096\n");
    fprintf(fout, "mon clock drift allowed = 60\n");
    fprintf(fout, "mon data avail warn = 15\n");
    fprintf(fout, "mon health preluminous compat warning = false\n");
    fprintf(fout, "mon allow pool delete = true\n");
    fprintf(fout, "mon warn on pool no redundancy = false\n");
    fprintf(fout, "mon client ping timeout = 10\n");
    fprintf(fout, "mon election timeout = 3\n");
    fprintf(fout, "mon osd report timeout = 20\n");
    fprintf(fout, "mon osd down out interval = 20\n");
    fprintf(fout, "mds beacon grace  = 10\n");
    fprintf(fout, "mds beacon mon down grace = 10\n");
    fprintf(fout, "mds reconnect timeout = 5\n");
    fprintf(fout, "mds cap revoke eviction timeout = 5\n");
    fprintf(fout, "ms mon client mode = crc\n");
    fprintf(fout, "osd max pg per osd hard ratio = 1.2\n");
    fprintf(fout, "osd crush chooseleaf type = 1\n");
    fprintf(fout, "osd pool default size = 1\n");
    fprintf(fout, "osd pool default min size = 1\n");
    fprintf(fout, "osd pool default pg autoscale mode = on\n");
    fprintf(fout, "rbd concurrent management ops = 20\n");

    // global perf tuning
    if (perfTuned) {
        fprintf(fout, "debug asok = 0/0\n");
        fprintf(fout, "debug auth = 0/0\n");
        fprintf(fout, "debug bdev = 0/0\n");
        fprintf(fout, "debug bluefs = 0/0\n");
        fprintf(fout, "debug bluestore = 0/0\n");
        fprintf(fout, "debug buffer = 0/0\n");
        fprintf(fout, "debug civetweb = 0/0\n");
        fprintf(fout, "debug client = 0/0\n");
        fprintf(fout, "debug compressor = 0/0\n");
        fprintf(fout, "debug context = 0/0\n");
        fprintf(fout, "debug crush = 0/0\n");
        fprintf(fout, "debug crypto = 0/0\n");
        fprintf(fout, "debug dpdk = 0/0\n");
        fprintf(fout, "debug eventtrace = 0/0\n");
        fprintf(fout, "debug filer = 0/0\n");
        fprintf(fout, "debug filestore = 0/0\n");
        fprintf(fout, "debug finisher = 0/0\n");
        fprintf(fout, "debug fuse = 0/0\n");
        fprintf(fout, "debug heartbeatmap = 0/0\n");
        fprintf(fout, "debug javaclient = 0/0\n");
        fprintf(fout, "debug journal = 0/0\n");
        fprintf(fout, "debug journaler = 0/0\n");
        fprintf(fout, "debug kinetic = 0/0\n");
        fprintf(fout, "debug kstore = 0/0\n");
        fprintf(fout, "debug leveldb = 0/0\n");
        fprintf(fout, "debug lockdep = 0/0\n");
        fprintf(fout, "debug mds = 0/0\n");
        fprintf(fout, "debug mds balancer = 0/0\n");
        fprintf(fout, "debug mds locker = 0/0\n");
        fprintf(fout, "debug mds log = 0/0\n");
        fprintf(fout, "debug mds log expire = 0/0\n");
        fprintf(fout, "debug mds migrator = 0/0\n");
        fprintf(fout, "debug memdb = 0/0\n");
        fprintf(fout, "debug mgr = 0/0\n");
        fprintf(fout, "debug mgrc = 0/0\n");
        fprintf(fout, "debug mon = 0/0\n");
        fprintf(fout, "debug monc = 0/00\n");
        fprintf(fout, "debug ms = 0/0\n");
        fprintf(fout, "debug none = 0/0\n");
        fprintf(fout, "debug objclass = 0/0\n");
        fprintf(fout, "debug objectcacher = 0/0\n");
        fprintf(fout, "debug objecter = 0/0\n");
        fprintf(fout, "debug optracker = 0/0\n");
        fprintf(fout, "debug osd = 0/0\n");
        fprintf(fout, "debug paxos = 0/0\n");
        fprintf(fout, "debug perfcounter = 0/0\n");
        fprintf(fout, "debug rados = 0/0\n");
        fprintf(fout, "debug rbd = 0/0\n");
        fprintf(fout, "debug rbd mirror = 0/0\n");
        fprintf(fout, "debug rbd replay = 0/0\n");
        fprintf(fout, "debug refs = 0/0\n");
        fprintf(fout, "debug reserver = 0/0\n");
        fprintf(fout, "debug rgw = 0/0\n");
        fprintf(fout, "debug rocksdb = 0/0\n");
        fprintf(fout, "debug striper = 0/0\n");
        fprintf(fout, "debug throttle = 0/0\n");
        fprintf(fout, "debug timer = 0/0\n");
        fprintf(fout, "debug tp = 0/0\n");
        fprintf(fout, "debug xio = 0/0\n");
    }

    if (IsControl(s_eCubeRole)) {
        char mdsdir[256];

        snprintf(mdsdir, sizeof(mdsdir), MDSDIR_FMT, hostname.c_str());

        fprintf(fout, "[mds.%s]\n", hostname.c_str());
        fprintf(fout, "host = %s\n", hostname.c_str());
        if (!mdsIplist.empty())
            fprintf(fout, "mon host = %s\n", mdsIplist.c_str());
    }

    if (IsControl(s_eCubeRole)) {
        char nssdir[256];

        snprintf(nssdir, sizeof(nssdir), RGWDIR_FMT "/nss", hostname.c_str());

        fprintf(fout, "[mgr]\n");
        fprintf(fout, "mon pg warn max object skew = 0\n");

        // only control node runs rgw
        fprintf(fout, "[client.rgw.%s]\n", hostname.c_str());
        fprintf(fout, "host = %s\n", hostname.c_str());
        fprintf(fout, "rgw socket path = /tmp/radosgw-%s.sock\n", hostname.c_str());
        fprintf(fout, "log file = /var/log/ceph/ceph-rgw-%s.log\n", hostname.c_str());
        fprintf(fout, "rgw data = /var/lib/ceph/radosgw/ceph-rgw.%s\n", hostname.c_str());
        fprintf(fout, "rgw frontends = beast endpoint=%s:8888\n", myip.c_str());

        // Keystone information
        fprintf(fout, "rgw keystone api version = 3\n");
        fprintf(fout, "rgw keystone url = http://%s:5000\n", sharedId.c_str());
        fprintf(fout, "rgw keystone admin user = admin_cli\n");
        fprintf(fout, "rgw keystone admin password = %s\n", adminCliPass.c_str());
        fprintf(fout, "rgw keystone admin project = admin\n");
        fprintf(fout, "rgw keystone admin domain = default\n");
        fprintf(fout, "rgw keystone accepted roles = _member_, admin\n");
        fprintf(fout, "rgw keystone token cache size = 0\n");
        fprintf(fout, "rgw keystone revocation interval = 0\n");
        fprintf(fout, "rgw keystone implicit tenants = false\n");
        fprintf(fout, "rgw keystone make new tenants = true\n");
        fprintf(fout, "rgw s3 auth use keystone = true\n");
        fprintf(fout, "rgw keystone verify ssl = false\n");
        fprintf(fout, "rgw swift account in url = true\n");
        fprintf(fout, "# nss db path = %s\n", nssdir);

        // telemetry integration
        fprintf(fout, "rgw enable usage log = true\n");
        fprintf(fout, "rgw usage log tick interval = 30\n");
        fprintf(fout, "rgw usage log flush threshold = 1024\n");
        fprintf(fout, "rgw usage max shards = 32\n");
        fprintf(fout, "rgw usage max user shards = 1\n");

        // manila share
        // FIXME: Check if manila is enabled
        fprintf(fout, "[client.manila]\n");
        fprintf(fout, "client mount uid = 0\n");
        fprintf(fout, "client mount gid = 0\n");
        fprintf(fout, "log file = /var/log/ceph/ceph-client.manila.log\n");
        fprintf(fout, "admin socket = /var/run/ceph/guests/ceph-$name.$pid.asok\n");
    }

    if (IsControl(s_eCubeRole) || IsCompute(s_eCubeRole)) {
        fprintf(fout, "[client]\n");
        if (IsControl(s_eCubeRole)) {
            fprintf(fout, "rbd mirror journal max fetch bytes = 33554432\n");
        }
        if (IsCompute(s_eCubeRole)) {
            fprintf(fout, "rbd cache = true\n");
            fprintf(fout, "rbd cache writethrough until flush = true\n");
            fprintf(fout, "rbd journal pool = cachepool\n");
            fprintf(fout, "rbd journal max payload bytes = 8388608\n");
            fprintf(fout, "admin socket = /var/run/ceph/guests/$cluster-$type.$id.$pid.$cctid.asok\n");
            fprintf(fout, "log file = /var/log/qemu/qemu-guest-$pid.log\n");
        }
    }

    fprintf(fout, "[osd]\n");
    fprintf(fout, "osd heartbeat grace = 20\n");
    fprintf(fout, "osd heartbeat interval = 5\n");

    // bluestore osd perf tuning
    if (perfTuned) {
        fprintf(fout, "bluestore cache autotune = 0\n");
        fprintf(fout, "bluestore cache kv ratio = 0.2\n");
        fprintf(fout, "bluestore cache meta ratio = 0.8\n");
        fprintf(fout, "bluestore cache size ssd = 8G\n");
        fprintf(fout, "bluestore csum type = none\n");
        fprintf(fout, "bluestore extent map shard max size = 200\n");
        fprintf(fout, "bluestore extent map shard min size = 50\n");
        fprintf(fout, "bluestore extent map shard target size = 100\n");
        fprintf(fout, "bluestore rocksdb options = "
                        "compression=kNoCompression,"
                        "max_write_buffer_number=32,"
                        "min_write_buffer_number_to_merge=2,"
                        "recycle_log_file_num=32,"
                        "compaction_style=kCompactionStyleLevel,"
                        "write_buffer_size=67108864,"
                        "target_file_size_base=67108864,"
                        "max_background_compactions=31,"
                        "level0_file_num_compaction_trigger=8,"
                        "level0_slowdown_writes_trigger=32,"
                        "level0_stop_writes_trigger=64,"
                        "max_bytes_for_level_base=536870912,"
                        "compaction_threads=32,"
                        "max_bytes_for_level_multiplier=8,"
                        "flusher_threads=8,"
                        "compaction_readahead_size=2MB\n");
        fprintf(fout, "osd map share max epochs = 100\n");
        fprintf(fout, "osd max backfills = 5\n");
        fprintf(fout, "osd memory target = 2147483648\n");
        fprintf(fout, "osd op num shards = 8\n");
        fprintf(fout, "osd op num threads per shard = 2\n");
        fprintf(fout, "osd min pg log entries = 10\n");
        fprintf(fout, "osd max pg log entries = 10\n");
        fprintf(fout, "osd pg log dups tracked = 10\n");
        fprintf(fout, "osd pg log trim min = 10\n");
        fprintf(fout, "osd bench small size max iops = 1000000\n");
    }

    fclose(fout);

    return true;
}

static bool
UpdateMirrorConfig(bool enabled, const char* mysite,
                   const TuningStringArray& peerNameAry,
                   const TuningStringArray& peerIpAry,
                   const TuningStringArray& peerSecretAry)
{
    HexLogInfo("updating rbd mirror config files");
    HexSystemF(0, "rm -f " MIRROR_CONF_WILDCARD);

    if (!enabled)
        return true;

    HexSystemF(0, "ln -sf %s " MIRROR_CONF_FMT, CONF, mysite);

    for (unsigned i = 1 ; i < peerNameAry.size() ; i++) {
        char peerConf[256];
        std::string siteName = peerNameAry.newValue(i);
        std::string siteIp = peerIpAry.newValue(i);
        std::string secret = peerSecretAry.newValue(i);

        snprintf(peerConf, sizeof(peerConf), MIRROR_CONF_FMT, siteName.c_str());
        HexUtilSystemF(0, 0, HEX_SDK " ceph_basic_config_gen %s %s %s",
                             peerConf, siteIp.c_str(), secret.c_str());
    }

    return true;
}

static bool
CommitMon(bool enabled, const char* name, const char* hostname, const char* oldhostname, const char* myip, bool renew)
{
    HexUtilSystemF(FWD, 0, "systemctl stop ceph-mon@%s", hostname);

    HexUtilSystemF(0, 0, HEX_SDK " ceph_mon_store_renew");
    if (renew)
        HexUtilSystemF(0, 0, HEX_SDK " ceph_mon_map_renew %s %s", myip, oldhostname);

    if (enabled) {
        HexLogDebug("starting %s-mon service", name);

        HexUtilSystemF(0, 0, "systemctl start ceph-mon@%s", hostname);
        HexLogInfo("%s-mon is running", name);

        bool isMaster = G(IS_MASTER);
        if (!isMaster) {
            HexLogInfo("waiting for response of %s-mon", name);
            HexSystemF(0, "for i in 1 2 3 4 5 ; do ! timeout 60 ceph -s > /dev/null || break ; done");
            HexLogInfo("%s-mon is responding", name);
        }
    }
    else {
        HexLogInfo("%s-mon has been stopped", name);
    }

    return true;
}

static bool
RemoveMonData(const char* hostname)
{
    char mondir[256], marker[256];
    struct stat ds, ms;

    snprintf(mondir, sizeof(mondir), MONDIR_FMT, hostname);
    snprintf(marker, sizeof(marker), MAKRER_FMT, hostname);

    if (stat(mondir, &ds) == 0 && S_ISDIR(ds.st_mode) && stat(marker, &ms) == 0) {
        HexSystemF(0, "rm -rf %s", mondir);
        unlink(marker);
    }

    return true;
}

static bool
RemoveMon(const char* hostname)
{
    HexUtilSystemF(0, 0, "timeout 60 ceph mon remove %s", hostname);
    RemoveMonData(hostname);
    HexLogInfo("ceph-mon@%s removed", hostname);

    return true;
}

static bool
CommitMgr(const char* name, const char* hostname)
{
    if (!IsControl(s_eCubeRole))
        return true;

    std::string srv = std::string(name) + "-mgr@" + std::string(hostname);
    SystemdCommitService(true, srv.c_str());

    return true;
}

static bool
CommitMds(const char* name, const char* hostname)
{
    if (!IsControl(s_eCubeRole))
        return true;

    std::string srv = std::string(name) + "-mds@" + std::string(hostname);
    SystemdCommitService(true, srv.c_str());
    HexUtilSystemF(0, 0, HEX_SDK " ceph_fs_mds_init");

    return true;
}

static bool
CommitOsd(const char* name, bool restartAll = true)
{
    if (s_osdIds.size() == 0)
        return true;

    if (s_enabled) {
        HexLogDebug("starting %s-osd service", name);

        for (auto& id : (restartAll ? s_osdIds : s_osdNewIds)) {
            HexUtilSystemF(0, 0, HEX_SDK " ceph_osd_restart %lu", id);
        }

        HexLogInfo("%s-osd is running", name);
    }
    else {
        HexLogInfo("compact and stop %s-osd", name);
        for (auto& id : (restartAll ? s_osdIds : s_osdNewIds)) {
            HexUtilSystemF(FWD, 0, "timeout 600 ceph tell osd.%lu compact ; systemctl stop ceph-osd@%lu", id, id);
        }

        HexLogInfo("%s-osd has been stopped", name);
    }

    return true;
}

static bool
CommitRgw(const char* name, const char* hostname)
{
    if (!IsControl(s_eCubeRole))
        return true;

    if (s_enabled) {
        HexLogDebug("starting %s-rgw service", name);

        HexUtilSystemF(0, 0, "systemctl restart ceph-radosgw@rgw.%s", hostname);

        HexLogInfo("%s-rgw is running", name);
    }
    else {
        HexUtilSystemF(FWD, 0, "systemctl stop ceph-radosgw@rgw.%s", hostname);
        HexLogInfo("%s-rgw has been stopped", name);
    }

    return true;
}

static bool
CommitRbdMirror(const bool enabled, const ConfigString& site)
{
    if (!IsControl(s_eCubeRole))
        return true;

    if (!IsBootstrap() && enabled && site.oldValue() == site.newValue())
        return true;

    if (!IsBootstrap())
        HexUtilSystemF(0, 0, "systemctl stop ceph-rbd-mirror@%s-site", site.oldValue().c_str());

    if (enabled) {
        HexLogDebug("starting %s rbd-mirror service", site.c_str());
        HexUtilSystemF(0, 0, "systemctl reset-failed && systemctl start ceph-rbd-mirror@%s-site", site.c_str());

        HexLogInfo("%s rbd-mirror is running", site.c_str());
    }
    else {
        HexLogInfo("%s rbd-mirror has been stopped", site.c_str());
    }

    return true;
}
/*
static bool
CommitISCSI()
{

    HexSystemF(0, "systemctl stop rbd-target-gw");
    HexSystemF(0, "systemctl stop rbd-target-api");

    if (s_osdIds.size() == 0)
        return true;

    if (s_enabled) {
        HexUtilSystemF(0, 0, "systemctl start rbd-target-gw");
        HexUtilSystemF(0, 0, "systemctl start rbd-target-api");
        HexLogInfo("rbd-target services are running");
    }
    else {
        HexLogInfo("rbd-target services have been stopped");
    }

    return true;
}

// run after dashbaord module enabled
static bool
EnabledDashbaordISCSIGateway(const std::string myIp, const std::string gwApiPass)
{
    struct stat ms;

    if (stat(MAKRER_ISCSIGW, &ms) == 0)
        return true;

    if (s_osdIds.size() > 0)
        HexUtilSystemF(0, 0, HEX_SDK " ceph_dashboard_iscsi_gw_add %s %s", myIp.c_str(), gwApiPass.c_str());
    else
        HexUtilSystemF(0, 0, HEX_SDK " ceph_dashboard_iscsi_gw_rm");

    HexSystemF(0, "touch " MAKRER_ISCSIGW);

    return true;
}
*/
static bool
EnableMgrRestful()
{
    struct stat ms;

    if (!IsControl(s_eCubeRole) || stat(MAKRER_RESTFUL, &ms) == 0)
        return true;

    if (stat(MAKRER_RESTFUL, &ms) != 0) {
        HexUtilSystemF(0, 0, HEX_SDK " ceph_mgr_module_enable restful");
        HexSystemF(0, "timeout 10 ceph config-key set mgr/restful/crt -i %s 2>/dev/null", SRV_CRT);
        HexSystemF(0, "timeout 10 ceph config-key set mgr/restful/key -i %s 2>/dev/null", SRV_KEY);
        HexSystemF(0, "timeout 10 ceph config-key set mgr/restful/server_addr 0.0.0.0 2>/dev/null");
        HexSystemF(0, "timeout 10 ceph config-key set mgr/restful/server_port %s 2>/dev/null", RESTFUL_PORT);
        HexSystemF(0, "touch " MAKRER_RESTFUL);
    }

    return true;
}

/*
static bool
EnablePgAutoScale()
{
    struct stat ms;

    if (!IsControl(s_eCubeRole) || stat(MAKRER_AUTOSCALE, &ms) == 0)
        return true;

    if (stat(MAKRER_AUTOSCALE, &ms) != 0) {
        HexUtilSystemF(0, 0, HEX_SDK " ceph_mgr_module_enable pg_autoscaler");
        HexSystemF(0, "touch " MAKRER_AUTOSCALE);
    }

    return true;
}
*/

static bool
EnableMonMsgr2()
{
    struct stat ms;

    if (!IsControl(s_eCubeRole) || stat(MAKRER_MSGR2, &ms) == 0)
        return true;

    if (stat(MAKRER_MSGR2, &ms) != 0) {
        HexUtilSystemF(0, 0, HEX_SDK " ceph_mon_msgr2_enable");
        HexSystemF(0, "touch " MAKRER_MSGR2);
    }

    return true;
}

static bool
EnableMgrDashboard(const std::string& sharedId)
{
    struct stat ms;

    if (!IsControl(s_eCubeRole) || stat(MAKRER_DASHBOARD, &ms) == 0)
        return true;

    if (stat(MAKRER_DASHBOARD, &ms) != 0) {
        HexSystemF(0, "timeout 10 ceph config set mgr mgr/dashboard/server_addr 0.0.0.0 2>/dev/null");
        HexSystemF(0, "timeout 10 ceph config set mgr mgr/dashboard/ssl_server_port %s 2>/dev/null", s_ha ? DASHBOARD_HA_PORT : DASHBOARD_PORT);
        HexSystemF(0, "timeout 10 ceph config set mgr mgr/dashboard/ssl true 2>/dev/null");
        HexSystemF(0, "timeout 10 ceph config set mgr mgr/dashboard/url_prefix ceph 2>/dev/null");
        HexUtilSystemF(0, 0, HEX_SDK " ceph_mgr_module_enable dashboard");
        HexSystemF(0, "timeout 10 ceph config set mgr mgr/prometheus/server_addr 0.0.0.0 2>/dev/null");
        HexSystemF(0, "timeout 10 ceph config set mgr mgr/prometheus/server_port 9283 2>/dev/null");
        HexUtilSystemF(0, 0, HEX_SDK " ceph_mgr_module_enable prometheus");
        HexUtilSystemF(0, 0, HEX_SDK " ceph_mgr_module_enable osd_perf_query");
        HexSystemF(0, "touch " MAKRER_DASHBOARD);
    }

    return true;
}

static bool
InitCephClient(const std::string& master, const std::string& peer)
{
    struct stat ms;

    HexUtilSystemF(0, 0, "/sbin/modprobe rbd");

    if (stat(MAKRER_CLIENT, &ms) != 0) {
        if (peer != master) {
            HexUtilSystemF(0, 0, "rsync root@%s:%s %s 2>/dev/null", peer.c_str(), ADMIN_KEYRING, KEYRING_DIR);
            HexUtilSystemF(0, 0, "rsync root@%s:%s %s 2>/dev/null", peer.c_str(), K8S_KEYRING, KEYRING_DIR);
            HexUtilSystemF(0, 0, "rsync root@%s:%s %s 2>/dev/null", peer.c_str(), CEPHFS_CLIENT_AUTHKEY, KEYRING_DIR);
        }
        else {
            HexUtilSystemF(0, 0, "timeout 10 ceph auth get-or-create client.admin "
                                 "mon 'allow *' mds 'allow *' mgr 'allow *' osd 'allow *' -o %s", ADMIN_KEYRING);
            HexUtilSystemF(0, 0, "timeout 10 ceph auth get-or-create client.k8s "
                                 "mon 'allow r' osd 'allow rw pool=%s' -o %s", K8S_VOLUME, K8S_KEYRING);
            HexUtilSystemF(0, 0, "ceph-authtool -p %s > %s", ADMIN_KEYRING, CEPHFS_CLIENT_AUTHKEY);
            HexUtilSystemF(0, 0, "chmod 0600 %s", CEPHFS_CLIENT_AUTHKEY);
        }
        HexSystemF(0, "touch " MAKRER_CLIENT);
    }

    HexSystemF(0, "ln -sf %s %s", ADMIN_KEYRING, KEYRING_FILE);
    HexSystemF(0, "timeout 10 ceph config set client rbd_skip_partial_discard false 2>/dev/null"); // VMs with high I/O shut off by themselves

    return true;
}

static bool
MountCephfsStore()
{
    // Create mount point CEPHFS_STORE_DIR if not already
    if (HexMakeDir(CEPHFS_STORE_DIR, "root", "root", 0755) != 0) {
        HexLogWarning("failed to create cephfs store directory %s", CEPHFS_STORE_DIR);
        return false;
    }

    // Mount CEPHFS_STORE_DIR on local node
    HexUtilSystemF(0, 0, HEX_SDK " ceph_mount_cephfs");

    if (HexSystemF(0, "mountpoint -q %s", CEPHFS_STORE_DIR) == 0) {
        HexSystemF(0, "mkdir -p %s/backup", CEPHFS_STORE_DIR);
        HexSystemF(0, "mkdir -p %s/update", CEPHFS_STORE_DIR);
        HexSystemF(0, "mkdir -p %s/glance", CEPHFS_STORE_DIR);
        HexSystemF(0, "mkdir -p %s/k8s", CEPHFS_STORE_DIR);
        HexSystemF(0, "mkdir -p %s/nfs", CEPHFS_STORE_DIR);
        HexSystemF(0, "mkdir -p %s/nova/instances", CEPHFS_STORE_DIR);
        HexSetFileMode("/mnt/cephfs/glance", "root", "root", 0777);
        HexSetFileMode("/mnt/cephfs/nfs", "root", "root", 0777);
        HexSetFileMode("/mnt/cephfs/nova", "nova", "nova", 0755);
        HexSetFileMode("/mnt/cephfs/nova/instances", "nova", "nova", 0755);

        HexUtilSystemF(0, 0, "systemctl start ceph-umountfs");
        HexUtilSystemF(0, 0, "systemctl start nfs-ganesha");
    }

    return true;
}

static bool
Init()
{
    // fail safe for creating ceph guest socket dir
    HexMakeDir(CLIENT_SOCK, "ceph", "ceph", 0755);

    HexSystemF(0, "touch %s", DUMMY_KEYRING);

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
ParseCube(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 1);
    return true;
}

static bool
ParseKeystone(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 2);
    return true;
}

static void
NotifyNet(bool modified)
{
    s_bNetModified = s_hostname.modified();
}

static void
NotifyCube(bool modified)
{
    s_bCubeModified = IsModifiedTune(1);
    s_eCubeRole = GetCubeRole(s_cubeRole);
}

static void
NotifyKeystone(bool modified)
{
    s_bKeystoneModified = IsModifiedTune(2);
}

static bool
Validate()
{
    if (!IsBootstrap()) {
        if (!s_mirrorEnabled)
            return true;

        if (s_mirrorName.modified() | s_peerNameAry.modified()) {
            for (unsigned i = 1 ; i < s_peerNameAry.size() ; i++) {
                if (s_mirrorName.newValue() == s_peerNameAry.newValue(i)) {
                    HexLogError("Mirror local site name %s cannot be the same to remote site name %s", s_mirrorName.c_str(), s_mirrorName.c_str());
                    printf("Mirror local site name %s cannot be the same to remote site name %s\n", s_mirrorName.c_str(), s_mirrorName.c_str());
                    return false;
                }
            }
        }
    }

    return true;
}

static bool
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        s_bConfigChanged = true;
        s_bRbdMirrorChanged = true;
        return true;
    }

    s_bRbdMirrorChanged = s_mirrorEnabled.modified() | s_mirrorName.modified() |
                            s_peerNameAry.modified() | s_peerIpAry.modified() |
                          s_peerSecretAry.modified() | s_ruleVolumeAry.modified();

    s_bConfigChanged = s_enabled.modified() | s_debugEnabled.modified() |
                          s_fsid.modified() | s_monEnabled.modified() | s_perfTuned.modified() |
                             s_bNetModified | s_bCubeModified | s_bKeystoneModified |
                           G_MOD(IS_MASTER) | G_MOD(CTRL_IP) | G_MOD(SHARED_ID) |
                      G_MOD(STORAGE_F_CIDR) | G_MOD(STORAGE_B_CIDR) | G_MOD(STORAGE_F_ADDR);

    s_bMonMapChanged = s_bNetModified | G_MOD(STORAGE_F_ADDR);

    return s_bRbdMirrorChanged | s_bConfigChanged | s_bMonMapChanged;
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    if (s_bConfigChanged) {
        bool monEnabled = IsMonEnabled(s_ha, s_monEnabled, s_eCubeRole, s_ctrlHosts);
        bool isMaster = G(IS_MASTER);

        std::string fsid = s_fsid;
        std::string myIp = G(MGMT_ADDR);
        std::string ctrl = G(CTRL);
        std::string master = GetMaster(s_ha, ctrl, s_ctrlHosts);
        std::string ctrlIp = G(CTRL_IP);
        std::string sharedId = G(SHARED_ID);
        std::string pubNet = G(STORAGE_F_CIDR);
        std::string clstrNet = G(STORAGE_B_CIDR);
        std::string storIp = G(STORAGE_F_ADDR);
        std::string masterIp = storIp;
        std::string adminCliPass = GetSaltKey(s_saltkey, s_adminCliPass.newValue(), s_seed.newValue());
        std::string gwApiPass = GetSaltKey(s_saltkey, s_gwApiPass.newValue(), s_seed.newValue());
        std::string peer = master;
        std::string ctrlAddrs = s_ha ? s_ctrlAddrs : ctrlIp;

        int retry = 0;
        struct in_addr v4addr;
        do {
            if (!isMaster) {
                peer = GetMaster(s_ha, ctrlIp, s_ctrlAddrs);
                masterIp = HexUtilPOpen("ssh root@%s %s ceph_bootstrap_mon_ip 2>/dev/null", peer.c_str(), HEX_SDK);
            }

            HexLogInfo("got ceph monintor bootstrap ip %s from %s", masterIp.c_str(), peer.c_str());
            if (HexParseIP(masterIp.c_str(), AF_INET, &v4addr))
                break;
            else {
                HexLogWarning("invalid bootstrap ip address, try again");
                sleep(1);
            }
        } while (retry++ < 10);

        if (!HexParseIP(masterIp.c_str(), AF_INET, &v4addr)) {
            HexLogError("failed to get ceph monintor bootstrap ip");
            return false;
        }

        if (access(CONTROL_REJOIN, F_OK) == 0) {
            peer = GetControllerPeers(s_hostname, s_ctrlHosts)[0];
            master = HexUtilPOpen("ssh root@%s %s ceph_mon_map_hosts %s 2>/dev/null", peer.c_str(), HEX_SDK, CONF);
            masterIp = HexUtilPOpen("ssh root@%s %s ceph_mon_map_iplist %s 2>/dev/null", peer.c_str(), HEX_SDK, CONF);
        }

        UpdateConfig(fsid, ctrl, ctrlIp, sharedId, master, masterIp, pubNet, clstrNet, adminCliPass, s_perfTuned);
        UpdateISCSIConfig(ctrlAddrs, gwApiPass);

        if (!SetupMon(monEnabled, s_hostname, fsid, storIp.c_str(), isMaster))
            return false;

        CommitMon(monEnabled, NAME, s_hostname.c_str(), s_hostname.oldValue().c_str(),
                  storIp.c_str(), s_bMonMapChanged);
        EnableMonMsgr2();

        if (!monEnabled)
            RemoveMon(s_hostname.c_str());

        if (!SetupPools() ||
            !SetupFS() ||
            !SetupMgr(s_hostname) ||
            !SetupMds(s_hostname) ||
            !SetupRgw(s_hostname.c_str()) ||
            !SetupOsd(s_hostname, fsid) ||
            !SetupISCSI())
            return false;

        CommitMgr(NAME, s_hostname.c_str());
        CommitMds(NAME, s_hostname.c_str());
        CommitRgw(NAME, s_hostname.c_str());
        CommitOsd(NAME);
        // CommitISCSI();

        EnableMgrRestful();
        EnableMgrDashboard(sharedId);
        // EnabledDashbaordISCSIGateway(myIp, gwApiPass);
        // pg_autoscaler is always on module since pacific
        // EnablePgAutoScale();
        InitCephClient(master, peer);
        MountCephfsStore();
    }

    if (s_bRbdMirrorChanged && IsControl(s_eCubeRole)) {
        UpdateMirrorConfig(s_mirrorEnabled, s_mirrorName.c_str(),
                           s_peerNameAry, s_peerIpAry, s_peerSecretAry);

        CommitRbdMirror(s_mirrorEnabled, s_mirrorName);

        SetupRbdMirror(s_mirrorEnabled, s_mirrorMetaSync,
                       s_peerIpAry, s_peerSecretAry,
                       s_peerNameAry, s_ruleVolumeAry);
    }

    return true;
}

static bool
CommitIdp(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    if (!IsControl(s_eCubeRole))
        return true;

    std::string sharedId = G(SHARED_ID);
    std::string port = DASHBOARD_PORT;
    struct stat ms;

    if (stat(MAKRER_DASHBOARD_IDP, &ms) == 0)
        return true;

    HexUtilSystemF(0, 0, HEX_SDK " ceph_dashboard_idp_config %s %s", sharedId.c_str(), port.c_str());
    HexSystemF(0, "touch " MAKRER_DASHBOARD_IDP);

    return true;
}

static void
RestartMonUsage(void)
{
    fprintf(stderr, "Usage: %s restart_ceph_mon\n", HexLogProgramName());
}

static int
RestartMonMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartMonUsage();
        return EXIT_FAILURE;
    }

    bool monEnabled = IsMonEnabled(s_ha, s_monEnabled, s_eCubeRole, s_ctrlHosts);
    CommitMon(monEnabled, NAME, s_hostname.c_str(), NULL, NULL, false);

    return EXIT_SUCCESS;
}

static void
RestartMgrUsage(void)
{
    fprintf(stderr, "Usage: %s restart_ceph_mgr\n", HexLogProgramName());
}

static int
RestartMgrMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartMgrUsage();
        return EXIT_FAILURE;
    }

    CommitMgr(NAME, s_hostname.c_str());

    return EXIT_SUCCESS;
}

static void
RestartMdsUsage(void)
{
    fprintf(stderr, "Usage: %s restart_ceph_mds\n", HexLogProgramName());
}

static int
RestartMdsMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartMdsUsage();
        return EXIT_FAILURE;
    }

    CommitMds(NAME, s_hostname.c_str());

    return EXIT_SUCCESS;
}

static void
RestartOsdUsage(void)
{
    fprintf(stderr, "Usage: %s restart_ceph_osd\n", HexLogProgramName());
}

static int
RestartOsdMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartOsdUsage();
        return EXIT_FAILURE;
    }

    SetupOsd(s_hostname.newValue(), s_fsid.newValue());
    CommitOsd(NAME);

    return EXIT_SUCCESS;
}

static void
RefreshOsdUsage(void)
{
    fprintf(stderr, "Usage: %s refresh_ceph_osd\n", HexLogProgramName());
}

static int
RefreshOsdMain(int argc, char* argv[])
{
    if (argc != 1) {
        RefreshOsdUsage();
        return EXIT_FAILURE;
    }

    SetupOsd(s_hostname.newValue(), s_fsid.newValue());
    CommitOsd(NAME, false);

    return EXIT_SUCCESS;
}

static void
RestartRgwUsage(void)
{
    fprintf(stderr, "Usage: %s restart_ceph_rgw\n", HexLogProgramName());
}

static int
RestartRgwMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartRgwUsage();
        return EXIT_FAILURE;
    }

    CommitRgw(NAME, s_hostname.c_str());

    return EXIT_SUCCESS;
}

static void
RestartMirrorUsage(void)
{
    fprintf(stderr, "Usage: %s restart_ceph_mirror\n", HexLogProgramName());
}

static int
RestartMirrorMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartMirrorUsage();
        return EXIT_FAILURE;
    }

    CommitRbdMirror(s_mirrorEnabled.newValue(), s_mirrorName);

    return EXIT_SUCCESS;
}


static void
SyncConfigUsage(void)
{
    fprintf(stderr, "Usage: %s sync_ceph_config\n", HexLogProgramName());
}

static int
SyncConfigMain(int argc, char* argv[])
{
    if (argc != 1) {
        SyncConfigUsage();
        return EXIT_FAILURE;
    }

    // update ceph.conf for using current monmap hosts
    std::string fsid = s_fsid;
    std::string ctrl = G(CTRL);
    std::string ctrlIp = G(CTRL_IP);
    std::string sharedId = G(SHARED_ID);
    std::string pubNet = G(STORAGE_F_CIDR);
    std::string clstrNet = G(STORAGE_B_CIDR);
    std::string monHosts = HexUtilPOpen(HEX_SDK " ceph_mon_map_hosts %s", CONF);
    std::string monIplist = HexUtilPOpen(HEX_SDK " ceph_mon_map_iplist %s", CONF);
    std::string mdsIplist = HexUtilPOpen(HEX_SDK " ceph_mds_map_iplist %s", CONF);
    std::string adminCliPass = GetSaltKey(s_saltkey, s_adminCliPass.newValue(), s_seed.newValue());
    UpdateConfig(fsid, ctrl, ctrlIp, sharedId, monHosts, monIplist, pubNet, clstrNet, adminCliPass, s_perfTuned, mdsIplist);

    return EXIT_SUCCESS;
}

static void
RemoveMonUsage(void)
{
    fprintf(stderr, "Usage: %s remove_ceph_mon [force]\n", HexLogProgramName());
}

static int
RemoveMonMain(int argc, char* argv[])
{
    /*
     * [0]="remove_ceph_mon", [1]=[force]
     */
    if (argc > 2) {
        RemoveMonUsage();
        return EXIT_FAILURE;
    }

    bool force = false;
    if (argc == 2 && strncmp(argv[1], "force", 5) == 0)
        force = true;

    bool isMaster = G(IS_MASTER);

    if (!isMaster || force) {
        CommitMon(false, NAME, s_hostname.c_str(), NULL, NULL, false);
        RemoveMon(s_hostname.c_str());
    }

    return EXIT_SUCCESS;
}

static void
PurgeMonUsage(void)
{
    fprintf(stderr, "Usage: %s purge_ceph_mon\n", HexLogProgramName());
}

static int
PurgeMonMain(int argc, char* argv[])
{
    /*
     * [0]="purge_ceph_mon"
     */
    if (argc > 1) {
        PurgeMonUsage();
        return EXIT_FAILURE;
    }

    bool isMaster = G(IS_MASTER);

    CommitMon(false, NAME, s_hostname.c_str(), NULL, NULL, false);
    if (isMaster) {
        std::stringstream strPeers;
        std::vector<std::string> peers(0);
        peers = GetControllerPeers(s_hostname, s_ctrlHosts);
        copy(peers.begin(), peers.end(), std::ostream_iterator<std::string>(strPeers, ","));
        HexUtilSystemF(0, 0, HEX_SDK " ceph_mon_map_remove %s %s", CONF, strPeers.str().c_str());
        CommitMon(true, NAME, s_hostname.c_str(), NULL, NULL, false);
    }
    else {
        RemoveMonData(s_hostname.c_str());
    }

    return EXIT_SUCCESS;
}

static void
SetGuiPasswordUsage(void)
{
    fprintf(stderr, "Usage: %s change_ceph_gui_password <password>\n", HexLogProgramName());
}

static int
SetGuiPasswordMain(int argc, char* argv[])
{
    /*
     * [0]="change_ceph_gui_password", [1]=<password>
     */
    if (argc > 2) {
        SetGuiPasswordUsage();
        return EXIT_FAILURE;
    }

    HexUtilSystemF(0, 0, "timeout 10 ceph dashboard ac-user-set-password --force-password admin %s", argv[1]);

    return EXIT_SUCCESS;
}

static int
ClusterStartMain(int argc, char **argv)
{
    if (argc != 1) {
        return EXIT_FAILURE;
    }

    std::string myIp = G(MGMT_ADDR);
    std::string gwApiPass = GetSaltKey(s_saltkey, s_gwApiPass.newValue(), s_seed.newValue());
    std::string sharedId = G(SHARED_ID);
    std::string port = DASHBOARD_PORT;

    SyncConfigMain(1, NULL);
    SetupOsd(s_hostname.newValue(), s_fsid.newValue());

    HexUtilSystemF(0, 0, HEX_SDK " migrate_ceph");
    if (IsControl(s_eCubeRole)) {
        HexUtilSystemF(0, 0, HEX_SDK " ceph_dashboard_init %s", sharedId.c_str());
        HexUtilSystemF(0, 0, HEX_SDK " ceph_dashboard_idp_config %s %s", sharedId.c_str(), port.c_str());
    }
    /*
    if (s_osdIds.size() > 0)
        HexUtilSystemF(0, 0, HEX_SDK " ceph_dashboard_iscsi_gw_add %s %s", myIp.c_str(), gwApiPass.c_str());
    else
        HexUtilSystemF(0, 0, HEX_SDK " ceph_dashboard_iscsi_gw_rm");
    */
    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(restart_ceph_mon, RestartMonMain, RestartMonUsage);
CONFIG_COMMAND_WITH_SETTINGS(restart_ceph_mgr, RestartMgrMain, RestartMgrUsage);
CONFIG_COMMAND_WITH_SETTINGS(restart_ceph_mds, RestartMdsMain, RestartMdsUsage);
CONFIG_COMMAND_WITH_SETTINGS(restart_ceph_osd, RestartOsdMain, RestartOsdUsage);
CONFIG_COMMAND_WITH_SETTINGS(refresh_ceph_osd, RefreshOsdMain, RefreshOsdUsage);
CONFIG_COMMAND_WITH_SETTINGS(restart_ceph_rgw, RestartRgwMain, RestartRgwUsage);
CONFIG_COMMAND_WITH_SETTINGS(restart_ceph_mirror, RestartMirrorMain, RestartMirrorUsage);
CONFIG_COMMAND_WITH_SETTINGS(sync_ceph_config, SyncConfigMain, SyncConfigUsage);
CONFIG_COMMAND_WITH_SETTINGS(remove_ceph_mon, RemoveMonMain, RemoveMonUsage);
CONFIG_COMMAND_WITH_SETTINGS(purge_ceph_mon, PurgeMonMain, PurgeMonUsage);
CONFIG_COMMAND(change_ceph_gui_password, SetGuiPasswordMain, SetGuiPasswordUsage);

CONFIG_MODULE(ceph, Init, Parse, Validate, 0, Commit);
CONFIG_REQUIRES(ceph, haproxy);

CONFIG_MODULE(ceph_dashboard_idp, 0, 0, 0, 0, CommitIdp);
CONFIG_REQUIRES(ceph_dashboard_idp, keycloak);

// extra tunings
CONFIG_OBSERVES(ceph, net, ParseNet, NotifyNet);
CONFIG_OBSERVES(ceph, cubesys, ParseCube, NotifyCube);
CONFIG_OBSERVES(ceph, keystone, ParseKeystone, NotifyKeystone);

CONFIG_MIGRATE(ceph, "/var/lib/ceph");
CONFIG_MIGRATE(ceph, MAKRER_POOL);
CONFIG_MIGRATE(ceph, MAKRER_CEPHFS);
CONFIG_MIGRATE(ceph, MAKRER_CLIENT);
CONFIG_MIGRATE(ceph, ADMIN_KEYRING);
CONFIG_MIGRATE(ceph, K8S_KEYRING);

CONFIG_SUPPORT_COMMAND(HEX_SDK " ceph_status details");
CONFIG_SUPPORT_COMMAND("timeout 10 rados df");
CONFIG_SUPPORT_COMMAND("timeout 10 ceph osd tree");
CONFIG_SUPPORT_COMMAND_TO_FILE("timeout 60 ceph pg dump", "/tmp/ceph_pg_dump.txt");

CONFIG_TRIGGER_WITH_SETTINGS(ceph, "cluster_start", ClusterStartMain);

//CONFIG_SHUTDOWN(ceph, ShutdownCeph);
