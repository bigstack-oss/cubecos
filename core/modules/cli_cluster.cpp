// HEX SDK

#include <unistd.h>
#include <pthread.h>

#include <netinet/ip.h>
#include <arpa/inet.h>

#include <list>

#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/log.h>
#include <hex/strict.h>
#include <hex/parse.h>
#include <hex/string_util.h>

#include <hex/cli_module.h>
#include <hex/cli_util.h>

#include <cube/config_file.h>
#include <cube/cubesys.h>

#define CUBECTL "/usr/local/bin/cubectl"

#define CNR_H_FMT " %16s  %6s  %s"
#define CNR_FMT " %16s  %6s  [%s]\n"

template <typename T>
struct reversion_wrapper { T& iterable; };

template <typename T>
auto begin (reversion_wrapper<T> w) { return std::rbegin(w.iterable); }

template <typename T>
auto end (reversion_wrapper<T> w) { return std::rend(w.iterable); }

template <typename T>
reversion_wrapper<T> reverse (T&& iterable) { return { iterable }; }

#define SRVS    \
    C(ClusterLink) SEP C(ClusterSys) SEP C(ClusterSettings) SEP C(HaCluster) SEP  \
    C(MsgQueue) SEP C(IaasDb) SEP C(VirtualIp) SEP C(Storage) SEP    \
    C(ApiService) SEP C(SingleSignOn) SEP C(Compute) SEP C(Baremetal) SEP C(Network) SEP C(Image) SEP   \
    C(BlockStor) SEP C(FileStor) SEP C(ObjectStor) SEP C(Orchestration) SEP   \
    C(LBaaS) SEP C(DNSaaS) SEP C(K8SaaS) SEP C(InstanceHa) SEP \
    C(BusinessLogic) SEP C(DataPipe) SEP C(Metrics) SEP C(LogAnalytics) SEP  \
    C(Notifications) SEP C(Node)

#define EDGE_SRVS    \
    C(ClusterLink) SEP C(ClusterSys) SEP C(ClusterSettings) SEP C(HaCluster) SEP  \
    C(MsgQueue) SEP C(IaasDb) SEP C(VirtualIp) SEP C(Storage) SEP    \
    C(ApiService) SEP C(SingleSignOn) SEP C(Compute) SEP C(Network) SEP C(Image) SEP   \
    C(BlockStor) SEP C(FileStor) SEP C(ObjectStor) SEP C(Orchestration) SEP   \
    C(LBaaS) SEP C(InstanceHa) SEP C(DataPipe) SEP C(Metrics) SEP C(LogAnalytics) SEP  \
    C(Notifications) SEP C(Node)

#define C(x) x,
#define SEP
enum srvs { SRVS TOP };
#undef C
#define C(x) #x,
static std::string S[] = { SRVS };
#undef C
#define C(x) #x
#undef SEP
#define SEP "\n"
static std::string SRVCMD = "echo '" + std::string(SRVS) + "'";
static std::string E_SRVCMD = "echo '" + std::string(EDGE_SRVS) + "'";
#undef SEP
#define SEP "|"
static const char *HealthUsage = "health [<" SRVS ">]";
static const char *CheckUsage = "check [<" SRVS ">]";
static const char *CheckRepairUsage = "check_repair [<" SRVS ">]";
static const char *E_HealthUsage = "health [<" EDGE_SRVS ">]";
static const char *E_CheckUsage = "check [<" EDGE_SRVS ">]";
static const char *E_CheckRepairUsage = "check_repair [<" EDGE_SRVS ">]";
#undef C
#undef SEP

#define Q   15

enum caps {
    NO_REPORT = 0x1,
    NO_REPAIR = 0x2,
    NO_CHECK = 0x4
};

struct CompItem {
    int cap;
    int interval;
    int role = R_CONTROL;
};

typedef std::map<std::string, CompItem> CompMap;

CompMap s_comps = {
    { "link", { NO_REPAIR, 0, R_ALL } },
    { "clock", { 0, Q, R_ALL } },
    { "dns", { NO_REPAIR, 0, R_ALL } },
    { "bootstrap", { NO_REPAIR, 0, R_ALL } },
    { "license", { NO_REPAIR, 0, R_ALL } },
    { "nodelist", { NO_REPAIR, 0, R_ALL } },
    { "etcd", { 0, Q } },
    { "hacluster", { 0, Q } },
    { "rabbitmq", { 0, Q } },
    { "mysql", { 0, Q } },
    { "vip", { 0, Q } },
    { "haproxy_ha", { 0, Q } },
    { "haproxy", { 0, Q } },
    { "httpd", { 0, Q } },
    { "nginx", { 0, Q } },
    { "api", { 0, Q} },
    { "skyline", { 0, Q } },
    { "memcache", { 0, Q  } },
    { "keycloak", { 0, Q  } },
    { "ceph", { NO_REPAIR, Q } },
    { "ceph_mon", { 0, Q } },
    { "ceph_mgr", { 0, Q } },
    { "ceph_mds", { 0, Q } },
    { "ceph_osd", { 0, Q } },
    { "ceph_rgw", { 0, Q } },
    { "rbd_target", { 0, Q } },
    { "nova", { 0, Q } },
    { "cyborg", { 0, Q } },
    { "ironic", { 0, Q, R_CTRL_NOT_EDGE } },
    { "neutron", { 0, Q } },
    { "glance", { 0, Q } },
    { "cinder", { 0, Q } },
    { "manila", { 0, Q } },
    { "swift", { NO_REPAIR, Q } },
    { "heat", { 0, Q } },
    { "octavia", { 0, Q } },
    { "designate", { 0, Q, R_CTRL_NOT_EDGE } },
    { "k3s", { 0, Q } },
    { "rancher", { NO_REPAIR, Q, R_CTRL_NOT_EDGE } },
    { "masakari", { 0, Q } },
    { "zookeeper", { 0, Q } },
    { "kafka", { 0, Q } },
    { "monasca", { 0, Q } },
    { "senlin", { 0, Q, R_CTRL_NOT_EDGE } },
    { "watcher", { 0, Q, R_CTRL_NOT_EDGE } },
    { "telegraf", { 0, Q } },
    { "influxdb", { 0, Q } },
    { "kapacitor", { 0, Q } },
    { "grafana", { 0, Q } },
    { "filebeat", { 0, Q } },
    { "auditbeat", { 0, Q } },
    { "logstash", { 0, Q } },
    { "opensearch", { 0, Q, R_CTRL_NOT_EDGE } },
    { "opensearch-dashboards", { 0, Q, R_CTRL_NOT_EDGE } },
    { "node", { NO_REPAIR | NO_CHECK, 0 } },
    { "mongodb", { 0, Q } }
};

#define HAS_REPORT(c)   !(s_comps[c].cap & NO_REPORT)
#define HAS_REPAIR(c)   !(s_comps[c].cap & NO_REPAIR)
#define HAS_CHECK(c)    !(s_comps[c].cap & NO_CHECK)

struct CheckRepairItem {
    std::string display;
    std::string comps;
    bool failthru;
    int role = R_CONTROL;
    int level = BLVL_DONE;
};

CheckRepairItem s_services[] = {
    { S[ClusterLink], "link,clock,dns", false, R_ALL, BLVL_STD },
    { S[ClusterSys], "bootstrap,license", false, R_ALL, BLVL_STD },
    { S[ClusterSettings], "etcd,nodelist,mongodb", false },
    { S[HaCluster], "hacluster", false },
    { S[MsgQueue], "rabbitmq", false },
    { S[IaasDb], "mysql", false },
    { S[VirtualIp], "vip,haproxy_ha", false },
    { S[Storage], "ceph,ceph_mon,ceph_mgr,ceph_mds,ceph_osd,ceph_rgw,rbd_target", true, R_ALL },
    { S[ApiService], "haproxy,httpd,nginx,api,skyline,memcache", false },
    { S[SingleSignOn], "k3s,keycloak", false },
    { S[Network], "neutron", false },
    { S[Compute], "nova,cyborg", true },
    { S[Baremetal], "ironic", true, R_CTRL_NOT_EDGE },
    { S[Image], "glance", true },
    { S[BlockStor], "cinder", true },
    { S[FileStor], "manila", true },
    { S[ObjectStor], "swift", true },
    { S[Orchestration], "heat", true },
    { S[LBaaS], "octavia", true },
    { S[DNSaaS], "designate", true, R_CTRL_NOT_EDGE },
    { S[K8SaaS], "rancher", true, R_CTRL_NOT_EDGE },
    { S[InstanceHa], "masakari", true },
    { S[BusinessLogic], "senlin,watcher", true, R_CTRL_NOT_EDGE },
    { S[DataPipe], "zookeeper,kafka", true },
    { S[Metrics], "monasca,telegraf,grafana", true },
    { S[LogAnalytics], "filebeat,auditbeat,logstash,opensearch,opensearch-dashboards", true },
    { S[Notifications], "influxdb,kapacitor", true },
    { S[Node], "node", true, R_ALL, BLVL_STD }
};

static bool
LoadMap(Configs *cfg)
{
    ConfigList settings;
    std::string parser = "jq -r .[].ip.management | sort | tr '\n' ',' | head -c -1";
    settings["all"] = HexUtilPOpen(CUBECTL " node list -j | %s", parser.c_str());
    settings["control"] = HexUtilPOpen(CUBECTL " node list -r control -j | %s", parser.c_str());
    settings["compute"] = HexUtilPOpen(CUBECTL " node list -r compute -j | %s", parser.c_str());
    settings["storage"] = HexUtilPOpen(CUBECTL " node list -r storage -j | %s", parser.c_str());

    (*cfg)[GLOBAL_SEC] = settings;

    return true;
}

static void
GetIpList(const std::string& ipranges, CliList* iplist)
{
    iplist->clear();
    std::vector<std::string> iprs = hex_string_util::split(ipranges, ',');

    for (auto& ipr : iprs) {
        uint32_t hfrom = 0, hto = 0;
        if (HexParseIPRange(ipr.c_str(), AF_INET, &hfrom, &hto)) {
            uint32_t from = htonl(hfrom);
            uint32_t to = htonl(hto);
            for (uint32_t ip = from ; ip <= to ; ip++) {
                struct in_addr ip_addr;
                ip_addr.s_addr = ntohl(ip);
                iplist->push_back(std::string(inet_ntoa(ip_addr)));
            }
        }
    }
}

#if 0
static void
GetTypeIpList(const std::string& types, CliList* iplist)
{
    CliList tIplist;
    Configs cfg;
    LoadMap(&cfg);

    iplist->clear();
    std::vector<std::string> tVec = hex_string_util::split(types, ',');
    for (auto& type : tVec) {
        GetIpList(cfg[GLOBAL_SEC][type], &tIplist);
        for (auto& ip : tIplist) {
            std::vector<std::string>::iterator it;
            it = std::find(iplist->begin(), iplist->end(), ip);
            if(it == iplist->end())
                iplist->push_back(ip);
        }
    }
}
#endif

static bool
ListCluster()
{
    Configs cfg;
    LoadMap(&cfg);

    char line[61];
    memset(line, '-', sizeof(line));
    line[sizeof(line) - 1] = 0;

#define CLS_H_FMT " %12s  %s"
#define CLS_FMT " %12s  %s\n"

    CliPrintf(CLS_H_FMT, "role", "map");
    CliPrintf("%s", line);
    printf(CLS_FMT, "all", cfg[GLOBAL_SEC]["all"].c_str());
    printf(CLS_FMT, "control", cfg[GLOBAL_SEC]["control"].c_str());
    printf(CLS_FMT, "compute", cfg[GLOBAL_SEC]["compute"].c_str());
    printf(CLS_FMT, "storage", cfg[GLOBAL_SEC]["storage"].c_str());
    CliPrintf("%s", line);

    return true;
}

static int
ClusterReportItem(const CheckRepairItem& item, bool check)
{
    if (item.level > CubeBootLevel())
        return 0;

    if (!CubeHasRole(item.role))
        return 0;

    bool title = false;
    std::vector<std::string> comps = hex_string_util::split(item.comps, ',');
    for (auto& c : comps) {
        if (!CubeHasRole(s_comps[c].role))
            continue;

        int ret = 0;
        if (check && !(s_comps[c].cap & NO_CHECK))
            ret = HexSystemF(0, HEX_SDK " health_%s_check", c.c_str());

        if ((!check || ret != 0) && HAS_REPORT(c)) {
            if (!title) {
                CliPrintf("\n[ %s ]", item.display.c_str());
                fflush(stdout);
                title = true;
            }

            CliPrintf("%s:", c.c_str());
            fflush(stdout);
            HexSystemF(0, HEX_SDK " health_%s_report", c.c_str());
        }
    }

    return 0;
}

static bool
ClusterReadyCheck()
{
    if (HexSystemF(0, HEX_SDK " cube_cluster_ready") != 0) {
        CliPrintf("WARNING! The cluster is not ready.");
        CliPrintf("Please check if you are missing \"cluster> set_ready\" in first time setup,");
        CliPrintf("missing \"boot> bootstrap_cube\" or \"boot> cluster_sync\" in node start,");
        CliPrintf("or missing \"cluster> start\" in cluster start.");
        return false;
    }

    return true;
}

void * ThreadClusterReportItem(void *thargs) {
    ClusterReportItem(*((CheckRepairItem*)thargs), true);
    return NULL;
}

static int
ClusterHealthNgMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="health_ng" */)
        return CLI_INVALID_ARGS;

    ClusterReadyCheck();

    pthread_t thread_id[TOP];
    for (int i = 0 ; i < TOP ; i++) {
        if (pthread_create(&thread_id[i], NULL, ThreadClusterReportItem, (void *)&s_services[i]) != 0) {
            CliPrintf("Failed to start threads in parallel %ld, %s.", (long)thread_id[i], s_services[i].display.c_str());
            return -1;
        }
    }
    for (int i = 0 ; i < TOP ; i++) pthread_join(thread_id[i], NULL);

    return CLI_SUCCESS;
}

static int
ClusterHealthMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="health" [1]="[service_name]" */)
        return CLI_INVALID_ARGS;

    ClusterReadyCheck();

    int index = -1;
    std::string service;

    if (argc == 2 && CliMatchCmdHelper(argc, argv, 1, CubeHasRole(R_CORE) ? E_SRVCMD : SRVCMD, &index, &service)) {
        CliPrintf("invalid service %s", service.c_str());
        return CLI_INVALID_ARGS;
    }

    CheckRepairItem srv;
    for (auto& s: s_services) {
        if (service == s.display)
            srv = s;
    }

    if (CubeBootLevel() != BLVL_DONE)
        CliPrintf("CubeCOS has yet to bootstrap!");

    if (index >= 0) {
        ClusterReportItem(srv, false);
    }
    else {
        for (int i = 0 ; i < TOP ; i++) {
            ClusterReportItem(s_services[i], false);
        }
    }

    return CLI_SUCCESS;
}

static int
ClusterCheckRepairItem(const CheckRepairItem& item, bool check, int repair)
{
    bool failed = false;
    std::string report = " ";
    std::string fixComps = "";
    std::vector<std::string> comps = hex_string_util::split(item.comps, ',');

    if (item.level > CubeBootLevel())
        return 0;

    if (!CubeHasRole(item.role))
        return 0;

    if (check) {
        for (auto& c : comps) {
            if (!CubeHasRole(s_comps[c].role))
                continue;

            if (!HAS_CHECK(c))
                continue;

            int ret = HexSystemF(0, "_OVERRIDE_MAX_ERR=1 " HEX_SDK " health_%s_check", c.c_str());
            failed |= (ret == 0) ? false : true;
            report += c + ((ret == 0) ? "(v) " : "(" + std::to_string(HexExitStatus(ret)) + " " + HexUtilPOpen(HEX_SDK " health_errcode_lookup %s %d", c.c_str(), HexExitStatus(ret)) + ") ");

            if (ret != 0 && repair > 0 && HAS_REPAIR(c)) {
                fixComps += c + ",";
            }
        }

        if (report != " ")
            printf(CNR_FMT, item.display.c_str(),
                            failed ? (fixComps.length() ? "FIXING" : "NG") : "ok",
                            report.c_str());
        failed = false;
        report = " ";
        comps = hex_string_util::split(fixComps, ',');
    }

    for (auto& c : comps) {
        if (!HAS_REPAIR(c) || !HAS_CHECK(c))
            continue;

        int fixed;
        int fixCount = 1;
        do {
            HexSystemF(0, HEX_SDK " health_%s_repair", c.c_str());
            for (int i = 0 ; i < 3 ; i++) {
                sleep(s_comps[c].interval);
                fixed = HexSystemF(0, HEX_SDK " health_%s_check", c.c_str());
                if (fixed == 0)
                    break;
            }
            HexLogInfo("component %s %d time (max: %d) repair result: %d",
                       c.c_str(), fixCount, repair, fixed);
        } while (fixed != 0 && fixCount++ < repair);

        failed |= (fixed == 0) ? false : true;
        report += c + ((fixed == 0) ? "(f" + std::to_string(fixCount) + ") " : "(" + std::to_string(HexExitStatus(fixed)) + ") ");
    }

    if (report != " ")
        printf(CNR_FMT, check ? "" : item.display.c_str(), failed ? "FAIL" : "ok", report.c_str());

    return failed ? -1 : 0;
}

static int
ClusterRepairMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="repair" [1]="[service_name]" */)
        return CLI_INVALID_ARGS;

    if (!ClusterReadyCheck()) {
        CliPrintf("\n");
        CliPrintf("Cannot run this command when the cluster is not ready.");
        return CLI_SUCCESS;
    }

    int index;
    std::string comp;
    CliList options;

    for (auto& c : s_comps) {
        if (c.second.cap & NO_REPAIR)
            continue;

        if (!CubeHasRole(c.second.role))
            continue;

        options.push_back(c.first);
    }

    if (CliMatchListHelper(argc, argv, 1, options, &index, &comp, "Select a component:") != 0) {
        CliPrintf("invalid component %s", comp.c_str());
        return CLI_INVALID_ARGS;
    }

    printf("fixing %s ...", comp.c_str());
    fflush(stdout);
    HexSystemF(0, HEX_SDK " health_%s_repair", comp.c_str());
    printf("done\n");

    return CLI_SUCCESS;
}

void * ThreadClusterCheckRepairItem(void *thargs) {
    ClusterCheckRepairItem(*((CheckRepairItem*)thargs), true, 0);
    return NULL;
}

static int
ClusterCheckRepairMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="check/check_repair" [1]="[service_name]" [2]="[times]" */)
        return CLI_INVALID_ARGS;

    int index = -1;
    int repair = 0;
    std::string service;

    if (strcmp(argv[0], "check_repair") == 0) {
        repair = 1;
        if (argc >= 3 && argv[2]) {
            repair = atoi(argv[2]);
        }
    }

    if (HexSystemF(0, HEX_SDK " cube_remote_cluster_check") == 0)
        return CLI_SUCCESS;

    if (!ClusterReadyCheck() && repair) {
        CliPrintf("\n");
        CliPrintf("Cannot run this command when the cluster is not ready.");
        return CLI_SUCCESS;
    }

    if (argc >= 2 && CliMatchCmdHelper(argc, argv, 1, CubeHasRole(R_CORE) ? E_SRVCMD : SRVCMD, &index, &service)) {
        CliPrintf("invalid service %s", service.c_str());
        return CLI_INVALID_ARGS;
    }

    if (CubeBootLevel() != BLVL_DONE)
        CliPrintf("CubeCOS has not yet bootstrapped!");

    CheckRepairItem srv;
    for (auto& s: s_services) {
        if (service == s.display)
            srv = s;
    }

    CliPrintf(CNR_H_FMT, "Service", "Status", "Report");

    if (index >= 0) {
        ClusterCheckRepairItem(srv, true, repair);
    } else if (repair) {
        for (int i = 0 ; i < TOP ; i++) {
            int ret = ClusterCheckRepairItem(s_services[i], true, repair);
            if (ret != 0 && s_services[i].failthru == false) {
                CliPrint("A critical service could not be repaired. Stop checking.");
                break;
            }
        }
    } else {
        pthread_t thread_id[TOP];
        for (int i = 0 ; i < TOP ; i++) {
            if (pthread_create(&thread_id[i], NULL, ThreadClusterCheckRepairItem, (void *)&s_services[i]) != 0) {
                CliPrintf("Failed to start threads in parallel %ld, %s.", (long)thread_id[i], s_services[i].display.c_str());
                return -1;
            }
        }
        for (int i = 0 ; i < TOP ; i++) pthread_join(thread_id[i], NULL);
    }

    return CLI_SUCCESS;
}

static int
ClusterStopMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="stop" */)
        return CLI_INVALID_ARGS;

    if(!ListCluster())
        return CLI_FAILURE;

    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    Configs cfg;
    CliList iplist;

    LoadMap(&cfg);
    GetIpList(cfg[GLOBAL_SEC]["control"], &iplist);

    // get stop from the last node
    for (auto& ip : reverse(iplist)) {
        CliPrintf("mark control host %s down", ip.c_str());
        HexSystemF(0, "ssh root@%s '%s cube_cluster_stop' 2>/dev/null", ip.c_str(), HEX_SDK);
    }

    HexUtilSystemF(0, 0, HEX_SDK " ceph_osd_compact >/dev/null 2>&1");
    HexUtilSystemF(0, 0, HEX_SDK " ceph_enter_maintenance");

    return CLI_SUCCESS;
}

static int
ClusterPoweroffMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="all_shutdown" */)
        return CLI_INVALID_ARGS;

    if(!ListCluster())
        return CLI_FAILURE;

    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    Configs cfg;
    CliList iplist;
    std::string masterctl;

    LoadMap(&cfg);
    GetIpList(cfg[GLOBAL_SEC]["control"], &iplist);
    masterctl = iplist[0];

    for (auto& ip : reverse(iplist)) {
        CliPrintf("mark control host %s down", ip.c_str());
        HexSystemF(0, "ssh root@%s '%s cube_cluster_stop' 2>/dev/null", ip.c_str(), HEX_SDK);
        HexSystemF(0, "ssh root@%s 'systemctl stop nfs-ganesha'", ip.c_str());
    }

    HexUtilSystemF(0, 0, HEX_SDK " ceph_osd_compact >/dev/null 2>&1");
    HexUtilSystemF(0, 0, HEX_SDK " ceph_enter_maintenance");

    HexSystemF(0, "ssh root@%s '%s cube_cluster_power off' 2>/dev/null", masterctl.c_str(), HEX_SDK);

    return CLI_SUCCESS;
}

static int
ClusterPowercycleMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="all_reboot" */)
        return CLI_INVALID_ARGS;

    if(!ListCluster())
        return CLI_FAILURE;

    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    Configs cfg;
    CliList iplist;
    std::string masterctl;

    LoadMap(&cfg);
    GetIpList(cfg[GLOBAL_SEC]["control"], &iplist);
    masterctl = iplist[0];

    for (auto& ip : reverse(iplist)) {
        CliPrintf("mark control host %s down", ip.c_str());
        HexSystemF(0, "ssh root@%s '%s cube_cluster_stop' 2>/dev/null", ip.c_str(), HEX_SDK);
        HexSystemF(0, "ssh root@%s 'systemctl stop nfs-ganesha'", ip.c_str());
    }

    HexUtilSystemF(0, 0, HEX_SDK " ceph_osd_compact >/dev/null 2>&1");
    HexUtilSystemF(0, 0, HEX_SDK " ceph_enter_maintenance");
    HexUtilSystemF(0, 0, HEX_SDK " os_maintain_segment_hosts"); // puts hosts in maintenance if ins-ha is enabled

    HexSystemF(0, "ssh root@%s '%s cube_cluster_power cycle' 2>/dev/null", masterctl.c_str(), HEX_SDK);

    return CLI_SUCCESS;
}

static int
ClusterRecreateMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="recreate" */)
        return CLI_INVALID_ARGS;

    if(!ListCluster())
        return CLI_FAILURE;

    CliPrint("Recreating cluster is an action that cannot be undone. Are you sure?");
    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    CliPrint("Do you really mean it?");
    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    Configs cfg;
    CliList iplist;

    LoadMap(&cfg);

    GetIpList(cfg[GLOBAL_SEC]["control"], &iplist);

    for (auto& ip : iplist) {
        CliPrintf("refresh endpoint snapshot for node %s", ip.c_str());
        if (HexSystemF(0, "ssh root@%s '%s os_endpoint_snapshot_create' 2>/dev/null", ip.c_str(), HEX_SDK) != 0) {
            CliPrintf("endpoint snapshot is mandatory for cluster recreation");
            return CLI_FAILURE;
        }
    }

    GetIpList(cfg[GLOBAL_SEC]["all"], &iplist);

    for (auto& ip : reverse(iplist)) {
        CliPrintf("mark host %s new", ip.c_str());
        HexSystemF(0, "ssh root@%s '%s cube_cluster_recreate' 2>/dev/null", ip.c_str(), HEX_SDK);
    }

    return CLI_SUCCESS;
}

static int
ClusterStartMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="start" */)
        return CLI_INVALID_ARGS;

    const char* ACTION = "check";

    CliPrintf("Starting cluster");
    HexSpawn(0, CUBECTL, "node", "exec", "-p", HEX_SDK, "-v", "cube_cluster_start", ZEROCHAR_PTR);

    // FIXME: workaround neutron services that aren't always in ready state
    HexUtilSystemF(0, 0, HEX_SDK " health_neutron_repair");

    ClusterCheckRepairMain(1, &ACTION);

    CliPrintf("Done");

    return CLI_SUCCESS;
}

static int
ClusterRemoveNodeMain(int argc, const char** argv)
{
    /*
     * [0]="remove_node", [1]=<hostname>
     */
    if (argc > 2)
        return CLI_INVALID_ARGS;

    int index;
    std::string hostname;

    std::string cmd = std::string(HEX_SDK) + " cube_data_node_list";
    if(CliMatchCmdHelper(argc, argv, 1, cmd, &index, &hostname) != CLI_SUCCESS) {
        CliPrintf("No failed host or invalid hostname");
        return CLI_SUCCESS;
    }

    CliPrintf("this command is only applicable for compute or storage nodes");
    CliPrintf("make sure its running instances have been properly terminated or migrated");
    CliPrintf("shutdown the target host before proceeding");

    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    HexUtilSystemF(0, 0, HEX_SDK " cube_node_remove %s", hostname.c_str());

    return CLI_SUCCESS;
}

static int
ClusterReadyMain(int argc, const char** argv)
{
    if (argc > 4) {
        return CLI_INVALID_ARGS;
    }

    struct in_addr v4addr;
    std::string cidr = "", gw = "", iplist = "";
    bool cfgFlatExt = false;

    CliPrintf("Storage disk configurations.");
    HexSpawn(0, HEX_SDK, " ceph_node_group_list", NULL, NULL);
    std::string osdCnt = HexUtilPOpen("timeout 5 ceph osd tree | grep osd | grep up | wc -l | xargs echo -n");

    if(osdCnt == "0") {
        CliPrintf("set_ready aborted due to zero running osd for cluster storage. Fix this before continuing!");
        return CLI_SUCCESS;
    }

    if (argc > 1) {
        cfgFlatExt = true;
    } else {
        CliPrintf("Create a shared external network?");
        if (CliReadConfirmation())
            cfgFlatExt = true;
    }

    if (cfgFlatExt) {
        if (!CliReadInputStr(argc, argv, 1, "Input public network in CIDR: ", &cidr) ||
            cidr.length() < 9 /* x.x.x.x/x */) {
            CliPrintf("Invalid CIDR %s\n", cidr.c_str());
            return CLI_INVALID_ARGS;
        }
        if (!CliReadInputStr(argc, argv, 2, "Input gateway of public network: ", &gw) ||
            !HexParseIP(gw.c_str(), AF_INET, &v4addr)) {
            CliPrintf("Invalid gateway %s\n", gw.c_str());
            return CLI_INVALID_ARGS;
        }
        if (!CliReadInputStr(argc, argv, 3, "Enter public network available IP list [IP,IP-IP]: ", &iplist) ||
            !HexParseIPList(iplist.c_str(), AF_INET)) {
            CliPrintf("Invalid IP list %s\n", iplist.c_str());
            return CLI_INVALID_ARGS;
        }
    }

    CliPrintf("[1/7] Updating storage replication rule");
    HexUtilSystemF(0, 0, HEX_SDK " host_local_run " HEX_SDK " ceph_pool_replicate_init");

    CliPrintf("[2/7] Checking SDN services");
    HexUtilSystemF(0, 0,  HEX_SDK " host_local_run " HEX_SDK " health_neutron_repair");

    CliPrintf("[3/7] Configuring modules");
    if (cfgFlatExt)
        HexSpawn(0, HEX_CFG, "-p", "trigger", "cluster_ready", cidr.c_str(), gw.c_str(), iplist.c_str(), ZEROCHAR_PTR);
    else
        HexSpawn(0, HEX_CFG, "-p", "trigger", "cluster_ready", ZEROCHAR_PTR);

    CliPrintf("[4/7] Starting cluster");
    HexUtilSystemF(0, 0, HEX_SDK " host_local_run cubectl node exec -p " HEX_SDK " cube_cluster_start");

    CliPrintf("[5/7] Strengthening password");
    HexUtilSystemF(0, 0, HEX_SDK " host_local_run cubectl node exec -p " HEX_CFG " cube_password_init");

    CliPrintf("[6/7] Cluster check and repair");
    HexSpawn(0, HEX_SDK, "host_local_run", "hex_cli", "-c", "cluster check_repair", ZEROCHAR_PTR);

    CliPrintf("[7/7] Global Information Tracker");
    HexUtilSystemF(0, 0, HEX_SDK " host_local_run " HEX_SDK " git_server_init");
    HexUtilSystemF(0, 0, "nohup " HEX_SDK " host_local_run cubectl node exec -p " HEX_SDK " git_client_init &");

    CliPrintf("Done");

    return CLI_SUCCESS;
}

static int
ClusterSetRolePasswordMain(int argc, const char** argv)
{
    if (argc > 5 /* [0]="set_role_password", [1]=<role>, [2]=<old_password>, [3]=<new_password>, [4]=<confirm_password> */)
        return CLI_INVALID_ARGS;

    if(!ListCluster())
        return CLI_FAILURE;

    Configs cfg;
    CliList options;
    int index = 0;
    std::string role, oldPass, newPass, confirmPass, opts = "";

    LoadMap(&cfg);

    options.push_back("all");
    options.push_back("control");
    options.push_back("compute");
    options.push_back("storage");

    if (CliMatchListHelper(argc, argv, 1, options, &index, &role) != 0) {
        CliPrintf("unknown role");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 2, "Enter old role password: ", &oldPass) || oldPass.length() <= 0) {
        CliPrintf("invalid old password\n");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 3, "Enter new role password: ", &newPass) || newPass.length() <= 0) {
        CliPrintf("no new password");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 4, "Confirm new role password: ", &confirmPass) || confirmPass.length() <= 0) {
        CliPrintf("no confirm password");
        return CLI_INVALID_ARGS;
    }

    if (newPass != confirmPass) {
        CliPrintf("New role password and confirmation do not match");
        return CLI_INVALID_ARGS;
    }

    if (role != "all")
        opts = "-r " + role;

    HexSystemF(0, "cubectl node exec %s -p " HEX_CFG " password %s %s", opts.c_str(), oldPass.c_str(), newPass.c_str());

    return CLI_SUCCESS;
}

static int
ClusterErrcodeDumpMain(int argc, const char** argv)
{
    /*
     * [0]="errcode_dump"
     */
    if (argc > 1)
        return CLI_INVALID_ARGS;

    HexSpawn(0, HEX_SDK, " health_errcode_dump", NULL, NULL);

    return CLI_SUCCESS;
}

CLI_MODE(CLI_TOP_MODE, "cluster", "Work with cube cluster.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired());

CLI_MODE_COMMAND("cluster", "health_ng", ClusterHealthNgMain, NULL,
    "cube health report for no good service.",
    "health_ng");

CLI_MODE_COMMAND("cluster", "health", ClusterHealthMain, NULL,
    "cube health report.",
    CubeHasRole(R_CORE) ? E_HealthUsage : HealthUsage);

CLI_MODE_COMMAND("cluster", "check", ClusterCheckRepairMain, NULL,
    "check cube services.",
    CubeHasRole(R_CORE) ? E_CheckUsage : CheckUsage);

CLI_MODE_COMMAND("cluster", "repair", ClusterRepairMain, NULL,
    "repair cube services.",
    "repair <[component]>");

CLI_MODE_COMMAND("cluster", "check_repair", ClusterCheckRepairMain, NULL,
    "check cube services and run repair if required.",
    CubeHasRole(R_CORE) ? E_CheckRepairUsage : CheckRepairUsage);

CLI_MODE_COMMAND("cluster", "stop", ClusterStopMain, NULL,
    "stop cube cluster.",
    "stop");

CLI_MODE_COMMAND("cluster", "start", ClusterStartMain, NULL,
    "start cube cluster.",
    "start");

CLI_MODE_COMMAND("cluster", "poweroff", ClusterPoweroffMain, NULL,
    "power off all nodes in cube cluster.",
    "poweroff");

CLI_MODE_COMMAND("cluster", "powercycle", ClusterPowercycleMain, NULL,
    "power cycle all nodes in cube cluster.",
    "powercycle");

CLI_MODE_COMMAND("cluster", "recreate", ClusterRecreateMain, NULL,
    "CAUTION! mark to recreate the cluster.",
    "recreate");

CLI_MODE_COMMAND("cluster", "remove_node", ClusterRemoveNodeMain, NULL,
    "remove a cube node from the cluster.",
    "remove_node [<hostname>]");

CLI_MODE_COMMAND("cluster", "set_ready", ClusterReadyMain, NULL,
    "Toggle system to finish configuration when all nodes are active.",
    "set_ready [<CIDR>] [<gateway>] [<IP,IP-IP>]");

CLI_MODE_COMMAND("cluster", "set_role_password", ClusterSetRolePasswordMain, NULL,
    "Set root/admin password for nodes of a given role.",
    "set_role_password <role> <old_password> <new_password> <confirm_password>");

CLI_MODE_COMMAND("cluster", "errcode_dump", ClusterErrcodeDumpMain, NULL,
    "dump all error codes defined for cluster.",
    "errcode_dump");
