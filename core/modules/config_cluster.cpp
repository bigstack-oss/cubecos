// HEX SDK

#include <signal.h>

#include <hex/log.h>
#include <hex/config_module.h>
#include <hex/dryrun.h>
#include <hex/process_util.h>


// struct ClusterNode {
//     std::string hostname;
//     std::string ip;
//     std::string role;
// };

// typedef std::map<std::string, ClusterNode> ClusterNodeMap;

// static ClusterNodeMap
// GetClusterNodeTable()
// {
//     ClusterNodeMap nodeTable;
//     for (auto t: s_clusterNodeTunings) {
//         int pos = t.first.find_first_of('.');
//         std::string memberId = t.first.substr(0, pos);
//         std::string attr = t.first.substr(pos+1);

//         if (nodeTable.find(memberId) == nodeTable.end()) {
//             nodeTable[memberId] = ClusterNode();
//         }

//         if (attr == "hostname") {
//             nodeTable[memberId].hostname = t.second;
//         } else if (attr == "ip") {
//             nodeTable[memberId].ip = t.second;
//         } else if (attr == "role") {
//             nodeTable[memberId].role = t.second;
//         } else if (attr == "data") {
//             continue;
//         } else {
//             HexLogWarning("Unsupported node attribute: %s", attr.c_str());
//         }
//     }

//     return nodeTable;
// }

// static bool
// WriteHosts(ClusterNodeMap nodeTable)
// {
//     FILE *fout = fopen(TEMP_HOSTS_FILE, "w");
//     if (!fout) {
//         HexLogError("Unable to write temp hosts: %s", TEMP_HOSTS_FILE);
//         return false;
//     }

//     fprintf(fout, HOST_MARK_START "\n");
//     for (auto node: nodeTable) {
//         fprintf(fout, "%s %s\n", node.second.ip.c_str(), node.second.hostname.c_str());
//     }
//     fprintf(fout, HOST_MARK_END "\n");
//     fclose(fout);

//     // Remove existing hosts
//     HexUtilSystemF(0, 0, "sed -i '/" HOST_MARK_START "/,/" HOST_MARK_END "/d' %s", HOSTS_FILE);
//     // Append temp hosts file
//     HexUtilSystemF(0, 0, "cat %s >> %s", TEMP_HOSTS_FILE, HOSTS_FILE);

//     return true;
// }


static bool
Commit(bool modified, int dryLevel)
{
    // TODO: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    HexUtilSystemF(0, 0, "cubectl config commit cluster host --stacktrace");

    return true;
}

CONFIG_MODULE(cluster, 0, 0, 0, 0, Commit);
// FIXME in /etc/hosts, cluster settings could be outdated and should honor settings from cubesys
CONFIG_REQUIRES(cluster, cube_scan);

// Terraform data
CONFIG_MIGRATE(cluster, "/var/lib/terraform/terraform.tfstate*");

// ETCD data
CONFIG_MIGRATE(cluster, "/var/lib/etcd.cube");
CONFIG_MIGRATE(cluster, "/etc/etcd/etcd.conf.yml");

// Cluster nodes
CONFIG_MIGRATE(cluster, "/etc/settings.cluster.json");
CONFIG_MIGRATE(cluster, "/etc/revision");
CONFIG_MIGRATE(cluster, "/etc/hosts");

CONFIG_MIGRATE(cluster, "/var/www/certs");

//CONFIG_FIRST(cluster);
