// CUBE SDK

#include "cluster.hpp"

#include <arpa/inet.h>
#include <ifaddrs.h>

#include <algorithm>
#include <fstream>
#include <sstream>

std::string ClusterCaCertFile()
{
    return access(CLUSTER_CA_CRT, F_OK) == 0 ? CLUSTER_CA_CRT : CLUSTER_SRV_CRT;
}

int GetControlWorkers(bool isConverged, bool isEdge)
{
    if (isEdge) {
        return 1;
    }

    int workers = 0;
    unsigned int totalCpus = std::thread::hardware_concurrency();
    // reserve more cpu and ram for converged nodes
    int multiple = isConverged ? 1 : 2;

#define MAX(x, y) (x > y ? x : y)
#define MIN(x, y) (x < y ? x : y)

    // worker must be greater than zero
    workers = MAX(totalCpus / ConvergedRatio * multiple, 1);
    // max 3 workers are best for responese time
    workers = MIN(workers, 3);

#undef MAX
#undef MIN

    return workers;
}

std::string
GetSaltBytesInBase64(bool saltkey, const int len, const std::string& key, const std::string& salt)
{
    std::string pass = key;

    if (!saltkey)
        return pass;

    HexCryptoGetBytesInBase64(len, key, salt, &pass);

    return pass;
}

std::string
GetSaltKey(bool saltkey, const std::string& key, const std::string& salt)
{
    std::string pass = key;

    if (!saltkey)
        return pass;

    HexCryptoGetPassphrase(16, key, salt, &pass);

    // replace all special characters appear in b64 encoding table
    std::replace(pass.begin(), pass.end(), '+', 'p'); // replace all + to p
    std::replace(pass.begin(), pass.end(), '/', 'S'); // replace all / to S
    std::replace(pass.begin(), pass.end(), '=', 'e'); // replace all = to e

    return pass;
}

std::string
GetControlId(bool isCtrl, std::string hostname, std::string controller)
{
    return isCtrl ? hostname : controller;
}

std::string
GetSharedId(bool isCtrl, bool ha, const std::string& ctrl, const std::string& ctrlVid)
{
    return (isCtrl && ha) ? ctrlVid : ctrl;
}

std::string
GetIfAddr(std::string ifname)
{
    char ipaddr[64] = { 0 };
    if (!GetIPAddr(ifname.c_str(), ipaddr, sizeof(ipaddr), AF_INET)) {
        HexLogError("failed to read %s ipv4 address, return 0.0.0.0", ifname.c_str());
        return "0.0.0.0";
    }

    return ipaddr;
}

std::string
GetControllerIp(bool isCtrl, std::string controllerIp, std::string mgmtIf)
{
    if (!isCtrl)
        return controllerIp;

    return GetIfAddr(mgmtIf);
}

std::size_t
GetClusterSize(bool ha, const std::string& clusterGroup)
{
    if (!ha)
        return 1;

    return hex_string_util::split(clusterGroup.c_str(), ',').size();
}

// hostname in MASTER_OVERRIDE, "" if none
static std::string
GetMasterOverride()
{
    std::ifstream f(MASTER_OVERRIDE);
    std::string host;
    f >> host;
    return host;
}

// the override's entry in a hostname or address group, "" if none
static std::string
MasterOverrideIn(const std::vector<std::string>& group)
{
    std::string host = GetMasterOverride();
    if (host.empty())
        return "";

    if (std::find(group.begin(), group.end(), host) != group.end())
        return host;

    // address group: map the hostname through /etc/hosts
    std::ifstream f("/etc/hosts");
    std::string line;
    while (std::getline(f, line)) {
        std::istringstream ss(line);
        std::string addr, name;
        if (!(ss >> addr) || addr[0] == '#')
            continue;
        while (ss >> name) {
            if (name == host && std::find(group.begin(), group.end(), addr) != group.end())
                return addr;
        }
    }

    return "";
}

bool IsMaster(bool isCtrl, const std::string& hostname, const std::string& clusterHosts)
{
    if (!isCtrl)
        return false;

    auto hosts = hex_string_util::split(clusterHosts, ',');

    if (hosts.size() == 0)
        return true;

    return (GetMaster(clusterHosts).compare(hostname) == 0);
}

std::string
GetMaster(const std::string& clusterGroup)
{
    auto groups = hex_string_util::split(clusterGroup, ',');

    if (groups.size() == 0)
        return "";

    std::string master = MasterOverrideIn(groups);
    return master.empty() ? groups[0] : master;
}

std::string
GetMaster(const bool ha, const std::string& controller, const std::string& controlGroup)
{
    if (!ha)
        return controller;
    else {
        std::string master = GetMaster(controlGroup);
        return master == "" ? controller : master;
    }
}

std::vector<std::string>
GetControllerPeers(const std::string& self, const std::string& controlGroup)
{
    auto hosts = hex_string_util::split(controlGroup, ',');
    std::vector<std::string> peers(0);

    // callers join peers[0]: put the override master first
    std::string master = MasterOverrideIn(hosts);
    if (!master.empty() && master != self)
        peers.push_back(master);

    for (auto host : hosts) {
        if (self != host && master != host)
            peers.push_back(host);
    }

    return peers;
}

bool IsLastControlNode(
    const std::string& hostname,
    const std::string& controlGroup)
{
    const std::vector<std::string> controls = hex_string_util::split(controlGroup, ',');
    const std::string lastControl = controls.back();

    return hostname == lastControl;
}

std::string
MemcachedServers(const bool ha, const std::string& controller, const std::string& clusterGroup)
{
    if (!ha)
        return controller + ":11211";
    else {
        auto group = hex_string_util::split(clusterGroup, ',');
        std::string servers = "";
        for (size_t i = 0; i < group.size(); i++) {
            servers += group[i] + ":11211";
            if (i + 1 < group.size())
                servers += ",";
        }

        return servers;
    }
}

// true if ip is assigned to an interface of this host
static bool
IsLocalAddress(const std::string& ip)
{
    struct ifaddrs* ifs = nullptr;
    if (getifaddrs(&ifs) != 0)
        return false;

    bool found = false;
    char buf[INET_ADDRSTRLEN];
    for (struct ifaddrs* i = ifs; i && !found; i = i->ifa_next) {
        if (!i->ifa_addr || i->ifa_addr->sa_family != AF_INET)
            continue;
        auto* sin = reinterpret_cast<struct sockaddr_in*>(i->ifa_addr);
        if (inet_ntop(AF_INET, &sin->sin_addr, buf, sizeof(buf)) && ip == buf)
            found = true;
    }
    freeifaddrs(ifs);
    return found;
}

std::string
RabbitMqServers(const bool ha, const std::string& controller,
    const std::string& pass, const std::string& clusterGroup, const bool ssl)
{
    const std::string port = ssl ? ":5671" : ":5672";

    if (!ha)
        return "rabbit://openstack:" + pass + "@" + controller + port;
    else {
        auto group = hex_string_util::split(clusterGroup, ',');
        // a control lists its own broker first, so a dead peer's broker never
        // holds this node's connections
        for (size_t i = 0; i < group.size(); i++) {
            if (IsLocalAddress(group[i])) {
                std::rotate(group.begin(), group.begin() + i, group.end());
                break;
            }
        }
        std::string servers = "rabbit://";
        for (size_t i = 0; i < group.size(); i++) {
            servers += "openstack:" + pass + "@" + group[i] + port;
            if (i + 1 < group.size())
                servers += ",";
        }

        return servers;
    }
}

void
SetMqClientConfig(Configs& config, const bool ha, const std::string& ctrlIp,
    const std::string& pass, const std::string& clusterGroup, const bool ssl,
    const bool withRpcTimeout)
{
    // Unconditional: every AMQP client gets these regardless of cluster shape.
    config["DEFAULT"]["transport_url"] = RabbitMqServers(ha, ctrlIp, pass, clusterGroup, ssl);

    // neutron's VPN agent is the sole call site that omits this.
    //
    // 60 is oslo.messaging's default and every service's own. It used to be 1200, which
    // made any RPC call whose reply was lost wait 20 minutes -- nova-compute's service
    // heartbeat among them: when a peer node froze, the survivor's heartbeat blocked for
    // the full 1200 s, nova reported the survivor down, and masakari had nowhere to
    // evacuate to. nova's known long calls use long_rpc_timeout instead. The services
    // with long synchronous calls of their own raise it after this: cinder, heat and
    // ironic.
    if (withRpcTimeout)
        config["DEFAULT"]["rpc_response_timeout"] = "60";

    // TLS is a property of the broker, not of the cluster shape, so this sits
    // outside the HA gate below: a single-node deployment pointed at 5671 needs
    // it exactly as much as a three-node one does.
    //
    // ssl_ca_file is what turns encryption into authentication -- oslo sets
    // cert_reqs=CERT_REQUIRED only when it is present (impl_rabbit.py
    // _fetch_ssl_params). It costs nothing in compatibility: oslo never passes
    // server_hostname to py-amqp, so the context runs with check_hostname off
    // and the appliance's self-signed cert validates as its own issuer without
    // needing the node's address in a SAN.
    //
    // ssl_cert_file / ssl_key_file stay unset: the broker runs
    // fail_if_no_peer_cert=false and clients still authenticate with the
    // openstack password. Mutual TLS is deferred.
    if (ssl) {
        config["oslo_messaging_rabbit"]["ssl"] = "true";
        config["oslo_messaging_rabbit"]["ssl_ca_file"] = ClusterCaCertFile();
    }

    // HA-gated: a single-node cluster has no peer to fail over to, so these
    // stay out of its configs entirely.
    if (ha) {
        config["oslo_messaging_rabbit"]["rabbit_retry_interval"] = "1";
        config["oslo_messaging_rabbit"]["rabbit_retry_backoff"] = "2";
        config["oslo_messaging_rabbit"]["amqp_durable_queues"] = "true";
        config["oslo_messaging_rabbit"]["rabbit_ha_queues"] = "true";
        // drop a dead broker in seconds, not the 60s default, so clients move to a live one
        config["oslo_messaging_rabbit"]["heartbeat_timeout_threshold"] = "15";
    }
}

std::string
KafkaServers(const bool ha, const std::string& controller, const std::string& clusterGroup, bool quote)
{
    std::string q = quote ? "\"" : "";

    if (!ha)
        return q + controller + ":9095" + q;
    else {
        auto group = hex_string_util::split(clusterGroup, ',');
        std::string servers = "";
        for (size_t i = 0; i < group.size(); i++) {
            servers += q + group[i] + ":9095" + q;
            if (i + 1 < group.size())
                servers += ",";
        }

        return servers;
    }
}

std::string
StorPubIf(const std::string& storage)
{
    auto group = hex_string_util::split(storage, ',');
    return group[0];
}

std::string
StorClusterIf(const std::string& storage)
{
    auto group = hex_string_util::split(storage, ',');
    return group[group.size() - 1];
}

std::string
GetMgmtCidrIp(const std::string& mgmtCidr, int idx, const std::string& octet)
{
    std::vector<std::string> comps = hex_string_util::split(mgmtCidr, '/');

    if (comps.size() != 2)
        return "10.254.0.0/16";

    std::string netid = comps[0];
    std::string netMask = comps[1];

    int oIdx = 2;
    if (netMask == "8")
        oIdx = 1;

    std::vector<std::string> octets = hex_string_util::split(netid, '.');
    int octetNum = std::stoi(octets[oIdx]) + (idx * 128);

    std::string prefix;
    if (oIdx == 1)
        prefix = octets[0] + "." + std::to_string(octetNum) + "." + octets[2] + ".";
    else
        prefix = octets[0] + "." + octets[1] + "." + std::to_string(octetNum) + ".";

    std::string suffix;
    if (octet.length())
        suffix = octet;
    else {
        if (oIdx == 1)
            suffix = octets[3] + "/9";
        else
            suffix = octets[3] + "/17";
    }

    return prefix + suffix;
}

std::string
GetMgmtCidr(const std::string& mgmtCidr, int idx)
{
    return GetMgmtCidrIp(mgmtCidr, idx, "");
}
