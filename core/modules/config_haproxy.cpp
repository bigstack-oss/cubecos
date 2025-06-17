// CUBE

#include <unistd.h>

#include <hex/log.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/filesystem.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>
#include <hex/string_util.h>

#include <cube/systemd_util.h>

#include "include/role_cubesys.h"

const static char NAME[] = "haproxy";
const static char CONF[] = "/etc/haproxy/haproxy.cfg";
const static char PIDFILE[] = "/var/run/haproxy.pid";

const static char NAME_HA[] = "haproxy-ha";
const static char CONF_HA[] = "/etc/haproxy/haproxy-ha.cfg";
const static char PIDFILE_HA[] = "/var/run/haproxy-ha.pid";

const static char USER[] = "haproxy";
const static char GROUP[] = "haproxy";
const static char RUNDIR[] = "/run/haproxy";

const static char KEYFILE[] = "/var/www/certs/server.pem";

static bool s_bCubeModified = false;
static CubeRole_e s_eCubeRole;

CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(SHARED_ID);


// private tunings
CONFIG_TUNING_BOOL(HAPROXY_ENABLED, "haproxy.enabled", TUNING_UNPUB, "Set to true to enable haproxy.", true);

// external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_VIP);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_HOSTS);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, PACEMAKER_ENABLED);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_ctrlVip, CUBESYS_CONTROL_VIP, 1);
PARSE_TUNING_X_STR(s_ctrlHosts, CUBESYS_CONTROL_HOSTS, 1);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);

static bool
WriteLocalConfig(bool ha, const std::string& myip, const std::string& sharedId)
{
    FILE *fout = fopen(CONF, "w");
    if (!fout) {
        HexLogError("Unable to write %s config: %s", NAME, CONF);
        return false;
    }

    fprintf(fout, "global\n");
    fprintf(fout, "  chroot /var/lib/haproxy\n");
    fprintf(fout, "  daemon\n");
    fprintf(fout, "  stats socket /run/haproxy/admin-local.sock mode 660 level admin\n");
    fprintf(fout, "  stats timeout 30s\n");
    fprintf(fout, "  maxconn 60000\n");
    fprintf(fout, "  pidfile %s\n", PIDFILE);
    fprintf(fout, "  user haproxy\n");
    fprintf(fout, "  group haproxy\n");
    fprintf(fout, "  log 127.0.0.1 syslog\n");
    fprintf(fout, "  tune.ssl.default-dh-param 2048\n");
    fprintf(fout, "  ssl-default-bind-options no-tlsv10\n");
    fprintf(fout, "\n");

    fprintf(fout, "defaults\n");
    fprintf(fout, "  log     global\n");
    fprintf(fout, "  maxconn 60000\n");
    fprintf(fout, "  option  redispatch\n");
    fprintf(fout, "  retries 3\n");
    fprintf(fout, "  timeout http-request 10s\n");
    fprintf(fout, "  timeout queue 1m\n");
    fprintf(fout, "  timeout connect 10s\n");
    fprintf(fout, "  timeout client  1m\n");
    fprintf(fout, "  timeout server  1m\n");
    fprintf(fout, "  timeout check   10s\n");
    fprintf(fout, "  \n");

    fprintf(fout, "listen stats\n");
    fprintf(fout, "  bind :9100\n");
    fprintf(fout, "  mode http\n");
    fprintf(fout, "  stats enable\n");
    fprintf(fout, "  stats hide-version\n");
    fprintf(fout, "  stats realm Haproxy\\ Statistics\n");
    fprintf(fout, "  stats uri /haproxy_stats\n");
    fprintf(fout, "  stats auth admin:Cube0s!\n");
    fprintf(fout, "  \n");

    fprintf(fout, "backend openstack_horizon\n");
    fprintf(fout, "  mode http\n");
    fprintf(fout, "  option forwardfor\n");
    fprintf(fout, "  option http-server-close\n");
    fprintf(fout, "  redirect scheme https if !{ ssl_fc }\n");
    fprintf(fout, "  server localhost 127.0.0.1:8080 check\n");
    fprintf(fout, "  \n");

    fprintf(fout, "backend rancher_node_driver\n");
    fprintf(fout, "  mode http\n");
    fprintf(fout, "  option forwardfor\n");
    fprintf(fout, "  option http-server-close\n");
    fprintf(fout, "  server localhost 127.0.0.1:8080 check\n");
    fprintf(fout, "  \n");

    fprintf(fout, "backend grafana_backend\n");
    fprintf(fout, "  mode http\n");
    fprintf(fout, "  option forwardfor\n");
    fprintf(fout, "  option http-server-close\n");
    fprintf(fout, "  http-request set-path %%[path,regsub(^/grafana/?,/)]\n");
    fprintf(fout, "  server localhost 127.0.0.1:3000 check\n");
    fprintf(fout, "  \n");

    if (!IsEdge(s_eCubeRole)) {
        fprintf(fout, "backend opensearch-dashboards_backend\n");
        fprintf(fout, "  mode http\n");
        fprintf(fout, "  option forwardfor\n");
        fprintf(fout, "  option http-server-close\n");
        fprintf(fout, "  server localhost 127.0.0.1:5601 check\n");
        fprintf(fout, "  \n");
    }

    fprintf(fout, "backend prometheus_backend\n");
    fprintf(fout, "  mode http\n");
    fprintf(fout, "  option forwardfor\n");
    fprintf(fout, "  option http-server-close\n");
    fprintf(fout, "  server localhost 127.0.0.1:9091 check\n");
    fprintf(fout, "  \n");

    fprintf(fout, "backend ceph_dashboard_backend\n");
    fprintf(fout, "  mode http\n");
    fprintf(fout, "  option forwardfor\n");
    fprintf(fout, "  option http-server-close\n");
    fprintf(fout, "  http-request replace-header Cookie (^|;)token=[^;]+;+(.*) \\1\\2\n");
    fprintf(fout, "  http-request replace-header Cookie (^|;)ceph_token=([^;]+)(.*) \\1token=\\2\\3\n");
    fprintf(fout, "  http-response replace-header Set-Cookie token=(.*) ceph_token=\\1\n");
    if (ha) {
        fprintf(fout, "  server localhost %s:7443 check ssl verify none\n", sharedId.c_str());
    } else {
        fprintf(fout, "  server localhost 127.0.0.1:7443 check ssl verify none\n");
    }
    fprintf(fout, "  \n");

    fprintf(fout, "frontend swift_api\n");
    fprintf(fout, "  bind :8890\n");
    fprintf(fout, "  mode http\n");
    fprintf(fout, "  use_backend swift_radosgw\n");
    fprintf(fout, "  \n");

    fprintf(fout, "backend swift_radosgw\n");
    fprintf(fout, "  mode http\n");
    fprintf(fout, "  option forwardfor\n");
    fprintf(fout, "  http-request replace-uri ([^/:]*://[^/]*)?(.*) \\1/swift\\2\n");
    fprintf(fout, "  server localhost %s:8888 check\n", myip.c_str());
    fprintf(fout, "  \n");

    fprintf(fout, "backend cube_cos_api\n");
    fprintf(fout, "  mode http\n");
    fprintf(fout, "  option forwardfor\n");
    fprintf(fout, "  option http-server-close\n");
    fprintf(fout, "  redirect scheme https if !{ ssl_fc }\n");
    fprintf(fout, "  http-request replace-header Cookie (^|;)token=[^;]+;+(.*) \\1\\2\n");
    fprintf(fout, "  http-request replace-header Cookie (^|;)cos_token=([^;]+)(.*) \\1token=\\2\\3\n");
    fprintf(fout, "  http-response replace-header Set-Cookie token=(.*) cos_token=\\1\n");
    fprintf(fout, "  server localhost %s:8082 check\n", myip.c_str());
    fprintf(fout, "  \n");

    fprintf(fout, "backend cube_cos_ui\n");
    fprintf(fout, "  mode http\n");
    fprintf(fout, "  option forwardfor\n");
    fprintf(fout, "  option http-server-close\n");
    fprintf(fout, "  redirect scheme https if !{ ssl_fc }\n");
    fprintf(fout, "  server localhost %s:8083 check\n", myip.c_str());
    fprintf(fout, "  \n");

    fprintf(fout, "frontend cube_cos_http\n");
    fprintf(fout, "  bind :80\n");
    fprintf(fout, "  mode http\n");
    fprintf(fout, "  option forwardfor\n");
    fprintf(fout, "  option http-server-close\n");
    fprintf(fout, "  http-request add-header X-Forwarded-Proto http\n");
    fprintf(fout, "  use_backend openstack_horizon if { path_beg /horizon }\n");
    fprintf(fout, "  use_backend rancher_node_driver if { path_beg /static/nodedrivers/ }\n");
    fprintf(fout, "  use_backend grafana_backend if { path_beg /grafana } or { path_beg /grafana/ }\n");
    if (!IsEdge(s_eCubeRole)) {
        fprintf(fout, "  use_backend opensearch-dashboards_backend if { path_beg /opensearch-dashboards } or { path_beg /opensearch-dashboards/ }\n");
    }
    fprintf(fout, "  use_backend prometheus_backend if { path_beg /prometheus } or { path_beg /prometheus/ }\n");
    fprintf(fout, "  use_backend ceph_dashboard_backend if { path_beg /ceph/ }\n");
    fprintf(fout, "  acl api_path path_beg /api/\n");
    fprintf(fout, "  acl saml_path path_beg /saml/\n");
    fprintf(fout, "  use_backend cube_cos_api if api_path or saml_path\n");
    fprintf(fout, "  default_backend cube_cos_ui\n");
    fprintf(fout, "  \n");

    // backend ceph_dashboard_backend and cube_cos_api should not use the same cookie name "token"
    fprintf(fout, "frontend cube_cos_https\n");
    fprintf(fout, "  bind :443 ssl crt %s\n", KEYFILE);
    fprintf(fout, "  mode http\n");
    fprintf(fout, "  option forwardfor\n");
    fprintf(fout, "  option http-server-close\n");
    fprintf(fout, "  http-request add-header X-Forwarded-Proto https\n");
    fprintf(fout, "  use_backend openstack_horizon if { path_beg /horizon }\n");
    fprintf(fout, "  use_backend rancher_node_driver if { path_beg /static/nodedrivers/ }\n");
    fprintf(fout, "  use_backend grafana_backend if { path_beg /grafana } or { path_beg /grafana/ }\n");
    if (!IsEdge(s_eCubeRole)) {
        fprintf(fout, "  use_backend opensearch-dashboards_backend if { path_beg /opensearch-dashboards } or { path_beg /opensearch-dashboards/ }\n");
    }
    fprintf(fout, "  use_backend prometheus_backend if { path_beg /prometheus } or { path_beg /prometheus/ }\n");
    fprintf(fout, "  use_backend ceph_dashboard_backend if { path_beg /ceph/ }\n");
    fprintf(fout, "  acl api_path path_beg /api/\n");
    fprintf(fout, "  acl saml_path path_beg /saml/\n");
    fprintf(fout, "  use_backend cube_cos_api if api_path or saml_path\n");
    fprintf(fout, "  default_backend cube_cos_ui\n");
    fprintf(fout, "  \n");

    fclose(fout);

    return true;
}


static bool
WriteConfig(bool ha, const std::string& ctrlVip,
            const std::string& ctrlHosts, const std::string& ctrlAddrs, const std::string& strfAddrs)
{
    FILE *fout = fopen(CONF_HA, "w");
    if (!fout) {
        HexLogError("Unable to write %s config: %s", NAME_HA, CONF_HA);
        return false;
    }

    fprintf(fout, "global\n");
    fprintf(fout, "  chroot /var/lib/haproxy\n");
    fprintf(fout, "  daemon\n");
    fprintf(fout, "  stats socket /run/haproxy/admin.sock mode 660 level admin\n");
    fprintf(fout, "  stats timeout 30s\n");
    fprintf(fout, "  maxconn 60000\n");
    fprintf(fout, "  pidfile %s\n", PIDFILE_HA);
    fprintf(fout, "  user haproxy\n");
    fprintf(fout, "  group haproxy\n");
    fprintf(fout, "  log 127.0.0.1 syslog\n");
    fprintf(fout, "  tune.ssl.default-dh-param 2048\n");
    fprintf(fout, "\n");

    fprintf(fout, "defaults\n");
    fprintf(fout, "  log     global\n");
    fprintf(fout, "  maxconn 60000\n");
    fprintf(fout, "  option  redispatch\n");
    fprintf(fout, "  retries 3\n");
    fprintf(fout, "  timeout http-request 10s\n");
    fprintf(fout, "  timeout queue 1m\n");
    fprintf(fout, "  timeout connect 10s\n");
    fprintf(fout, "  timeout client  10m\n");
    fprintf(fout, "  timeout server  10m\n");
    fprintf(fout, "  timeout check   10s\n");
    fprintf(fout, "  \n");

    fprintf(fout, "listen stats\n");
    fprintf(fout, "  bind :9000\n");
    fprintf(fout, "  mode http\n");
    fprintf(fout, "  stats enable\n");
    fprintf(fout, "  stats hide-version\n");
    fprintf(fout, "  stats realm Haproxy\\ Statistics\n");
    fprintf(fout, "  stats uri /haproxy_stats\n");
    fprintf(fout, "  stats auth admin:Cube0s!\n");
    fprintf(fout, "  \n");

    if (!ha) {
        fclose(fout);
        return true;
    }

    auto hosts = hex_string_util::split(ctrlHosts, ',');
    auto addrs = hex_string_util::split(ctrlAddrs, ',');
    auto strfs = hex_string_util::split(strfAddrs, ',');

    enum {
        SRV_NAME,
        SRV_PORT,
        SRV_CONN,
        SRV_OPTS
    };

    std::string srvlist[][4] = {
        { "galera", "3306", "mysql", "ap" },
        { "mongodb", "27017", "tcp", "ap" },
        { "keystone_api", "5000", "http", "" },
        { "glance_api", "9292", "http", "" },
        { "nova_compute_api", "8774", "http", "" },
        { "nova_metadata_api", "8775", "http", "" },
        { "nova_placement", "8778", "tcp", "" },
        { "nova_vncproxy", "6080", "tcp", "" },
        { "ironic_api", "6385", "http", "ctrl" },
        { "ironic_insp_api", "5050", "http", "ctrl" },
        { "ironic_file_srv", "8484", "http", "ctrl" },
        { "neutron_api", "9696", "http", "rr" },
        { "cinder_api", "8776", "http", "" },
        { "manila_api", "8786", "http", "" },
        { "swift_api", "8890", "tcp", "" },
        { "radosgw_proxy", "8888", "tcp", "" },
        { "heat_api", "8004", "http", "" },
        { "heat_api_cfn", "8000", "http", "" },
        { "barbican_api", "9311", "http", "ctrl" },
        { "masakari_api", "15868", "http", "" },
        { "monasca_api", "8070", "tcp", "notcpka" },
        { "octavia_api", "9876", "tcp", "" },
        { "designate_api", "9001", "http", "ctrl" },
        { "senlin_api", "8777", "http", "ctrl" },
        { "watcher_api", "9322", "tcp", "ctrl" },
        { "cyborg_api", "6666", "tcp", "ctrl" },
        { "memcache", "11211", "tcp", "" },
        { "opensearch", "9200", "http", "ctrl" },
        { "rabbitmq", "5672", "tcp", " clitcpka" },
        { "zookeeper", "2181", "tcp", "quorum" },
        { "kafka", "9095", "tcp", "" },
        { "mellon", "5443", "tcp", "" },
        { "skyline", "9999", "http", "" },
        { "cube_cos_api", "8082", "httpchk", "  option  httpchk GET /live" },
        { "cube_cos_ui", "8083", "http", "" },
        { "ceph_restful_api", "8005,8003", "tcp", "" },
        { "ceph_prometheus_ep", "9285,9283", "httpchk,strf", "  option  httpchk GET /metrics\n  http-check expect rstring .*ceph.*" },
        { "ceph_dashboard", "7443,7442", "httpschk", "  option  httpchk GET /ceph/\n  http-check expect status 200" },
        { "ceph_nfs_ganesha", "2049,2049", "tcp", "" }
    };

    for (size_t i = 0 ; i < sizeof(srvlist)/sizeof(srvlist[0]) ; i++) {
        if (srvlist[i][SRV_OPTS].find("quorum") != std::string::npos && hosts.size() < 3)
            continue;

        if (IsEdge(s_eCubeRole) && srvlist[i][SRV_OPTS].find("ctrl") != std::string::npos)
            continue;

        auto ports = hex_string_util::split(srvlist[i][SRV_PORT], ',');
        std::string fport = ports[0];
        std::string bport = ports[ports.size() - 1];

        fprintf(fout, "listen %s\n", srvlist[i][SRV_NAME].c_str());
        fprintf(fout, "  bind %s:%s\n", ctrlVip.c_str(), fport.c_str());

        if (srvlist[i][SRV_OPTS].find("rr") != std::string::npos)
            fprintf(fout, "  balance  roundrobin\n");
        else
            fprintf(fout, "  balance  source\n");

        if (srvlist[i][SRV_CONN] == "tcp") {
            if (srvlist[i][SRV_OPTS].find("clitcpka") != std::string::npos) {
                fprintf(fout, "  mode  tcp\n");
                fprintf(fout, "  timeout client  3h\n");
                fprintf(fout, "  timeout server  3h\n");
                fprintf(fout, "  option  clitcpka\n");
            }
        }
        else if (srvlist[i][SRV_CONN] == "http") {
            fprintf(fout, "  option  httpchk\n");
        }
        else if (srvlist[i][SRV_CONN].find("httpchk") != std::string::npos || srvlist[i][SRV_CONN].find("httpschk") != std::string::npos) {
            fprintf(fout, "%s\n", srvlist[i][SRV_OPTS].c_str());
        }
        else if (srvlist[i][SRV_CONN] == "mysql") {
            fprintf(fout, "  timeout client  10h\n");
            fprintf(fout, "  option  mysql-check\n");
        }

        if (srvlist[i][SRV_OPTS].find("notcpka") == std::string::npos)
            fprintf(fout, "  option  tcpka\n");

        fprintf(fout, "  option  tcplog\n");

        // we only talk to master node in upgrade
        int size = hosts.size();
        if (access(CUBE_MIGRATE, F_OK) == 0)
            size = 1;

        for (int n = 0 ; n < size ; n++) {
            std::string sslVerify = "";
            if (srvlist[i][SRV_CONN] == "httpschk")
                sslVerify = " check-ssl verify none";

            if (srvlist[i][SRV_CONN].find("strf") != std::string::npos && strfs.size() == (unsigned long)size) {
                if (srvlist[i][SRV_OPTS].find("ap") != std::string::npos)
                    fprintf(fout, "  server %s %s:%s %scheck inter 2000 rise 2 fall 5%s\n",
                                  hosts[n].c_str(), strfs[n].c_str(), bport.c_str(),
                                  n ? "backup " : "on-marked-down shutdown-sessions on-marked-up shutdown-backup-sessions ",
                                  sslVerify.c_str());
                else
                    fprintf(fout, "  server %s %s:%s check inter 2000 rise 2 fall 5%s\n",
                                  hosts[n].c_str(), strfs[n].c_str(), bport.c_str(), sslVerify.c_str());
            }
            else {
                if (srvlist[i][SRV_OPTS].find("ap") != std::string::npos)
                    fprintf(fout, "  server %s %s:%s %scheck inter 2000 rise 2 fall 5%s\n",
                                  hosts[n].c_str(), addrs[n].c_str(), bport.c_str(),
                                  n ? "backup " : "on-marked-down shutdown-sessions on-marked-up shutdown-backup-sessions ",
                                  sslVerify.c_str());
                else
                    fprintf(fout, "  server %s %s:%s check inter 2000 rise 2 fall 5%s\n",
                                  hosts[n].c_str(), addrs[n].c_str(), bport.c_str(), sslVerify.c_str());
            }
        }
        fprintf(fout, "\n");
    }

    fclose(fout);

    return true;
}

static bool
ParseCube(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 1);
    return true;
}

static void
NotifyCube(bool modified)
{
    s_bCubeModified = IsModifiedTune(1);
    s_eCubeRole = GetCubeRole(s_cubeRole);
}

static bool
Init()
{
    if (HexMakeDir(RUNDIR, USER, GROUP, 0755) != 0)
        return false;

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
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        return true;
    }

    return modified | G_MOD(MGMT_ADDR) | G_MOD(SHARED_ID) | s_bCubeModified;
}

static bool
Commit(bool modified, int dryLevel)
{
    // TODO: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsControl(s_eCubeRole) && !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = IsControl(s_eCubeRole) && s_enabled;
    std::string myip = G(MGMT_ADDR);
    std::string sharedId = G(SHARED_ID);
    std::string strfAddrs = HexUtilPOpen(HEX_SDK " cube_control_strf_addrs");

    WriteLocalConfig(s_ha, myip, sharedId);
    WriteConfig(s_ha, s_ctrlVip.newValue(), s_ctrlHosts.newValue(), s_ctrlAddrs.newValue(), strfAddrs);
    SystemdCommitService(enabled, NAME);
    SystemdCommitService(enabled, NAME_HA);

    return true;
}

static int
ClusterStartMain(int argc, char **argv)
{
    if (argc != 1) {
        return EXIT_FAILURE;
    }

    bool enabled = IsControl(s_eCubeRole) && s_enabled;
    std::string strfAddrs = HexUtilPOpen(HEX_SDK " cube_control_strf_addrs");

    // restore original haproxy-ha config in the case of upgrade
    WriteConfig(s_ha, s_ctrlVip.newValue(), s_ctrlHosts.newValue(), s_ctrlAddrs.newValue(), strfAddrs);
    SystemdCommitService(enabled, NAME_HA);

    return EXIT_SUCCESS;
}

CONFIG_MODULE(haproxy, Init, Parse, 0, 0, Commit);

// extra tunings
CONFIG_OBSERVES(haproxy, cubesys, ParseCube, NotifyCube);
CONFIG_REQUIRES(haproxy, pacemaker);

CONFIG_TRIGGER_WITH_SETTINGS(haproxy, "cluster_start", ClusterStartMain);

