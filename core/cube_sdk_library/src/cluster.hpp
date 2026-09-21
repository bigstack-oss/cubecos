// CUBE SDK

#ifndef CUBE_CLUSTER_H
#define CUBE_CLUSTER_H

#include <cube/config_file.h>
#include <cube/network.h>
#include <hex/crypto.h>
#include <hex/log.h>
#include <hex/string_util.h>

#include <algorithm>
#include <string>
#include <sys/socket.h>
#include <thread>
#include <unistd.h>
#include <vector>

#define ConvergedRatio 16

// The appliance's own PKI, distributed to every node by "cubectl config cluster".
#define CLUSTER_SRV_CRT "/var/www/certs/server.cert"
#define CLUSTER_SRV_KEY "/var/www/certs/server.key"
#define CLUSTER_CA_CRT  "/var/www/certs/ca.cert"

#define GetController(isctrl, hostname, controller) (isctrl ? hostname : controller)

int GetControlWorkers(
    bool isConverged,
    bool isEdge);

/**
 * The CA file that verifies this cluster's server.cert.
 *
 * The appliance signs its own server.cert and ships no separate CA, so the cert
 * is normally its own issuer. A ca.cert exists only where an operator installed
 * one; prefer it then. Broker and clients must resolve this the same way, which
 * is why it lives here rather than in either config module.
 */
std::string ClusterCaCertFile();

std::string
GetSaltBytesInBase64(
    bool saltkey,
    const int len,
    const std::string& key,
    const std::string& salt);

std::string
GetSaltKey(
    bool saltkey,
    const std::string& key,
    const std::string& salt);

std::string
GetControlId(
    bool isCtrl,
    std::string hostname,
    std::string controller);

std::string
GetSharedId(
    bool isCtrl,
    bool ha,
    const std::string& ctrl,
    const std::string& ctrlVid);

std::string
GetIfAddr(std::string ifname);

std::string
GetControllerIp(
    bool isCtrl,
    std::string controllerIp,
    std::string mgmtIf);

std::size_t GetClusterSize(
    bool ha,
    const std::string& clusterGroup);

bool IsMaster(
    bool isCtrl,
    const std::string& hostname,
    const std::string& clusterHosts);

std::string
GetMaster(const std::string& clusterGroup);

std::string GetMaster(
    const bool ha,
    const std::string& controller,
    const std::string& controlGroup);

std::vector<std::string>
GetControllerPeers(
    const std::string& self,
    const std::string& controlGroup);

/**
 * Check if the hostname is the last control node.
 *
 * @param hostname the control node name
 * @param controlGroup a string of comma separated control node names
 * @return true, if the hostname is the last control node
 */
bool IsLastControlNode(
    const std::string& hostname,
    const std::string& controlGroup);

std::string
MemcachedServers(
    const bool ha,
    const std::string& controller,
    const std::string& clusterGroup);

/**
 * Build the AMQP transport_url for one service.
 *
 * @p ssl selects the port only -- 5671 instead of 5672. The scheme stays
 * "rabbit://" either way: oslo.messaging registers no "rabbit+ssl" driver
 * (entry points are amqp/fake/kafka/kombu/rabbit), so TLS is turned on by the
 * oslo_messaging_rabbit "ssl" option that SetMqClientConfig() writes, never by
 * the URL. Changing the port without that option yields a plaintext client
 * knocking on the TLS listener.
 */
std::string
RabbitMqServers(
    const bool ha,
    const std::string& ctrlIp,
    const std::string& pass,
    const std::string& clusterGroup,
    const bool ssl);

/**
 * Write one service's AMQP client settings into @p config.
 *
 * Shared by every OpenStack service that talks to RabbitMQ so that the client
 * side has a single place to change. Role gating (IsControl / IsCompute) stays
 * with the caller: which roles run a given service is a property of that
 * service's deployment, not of the message queue.
 *
 * @p withRpcTimeout exists for neutron's VPN agent, which is the one call site
 * that has never carried rpc_response_timeout. Preserved deliberately; do not
 * "fix" it here without re-taking the generated-config evidence.
 *
 * @p ssl has no default on purpose: it sits before @p withRpcTimeout so that
 * every existing five-argument call fails to compile until it states which
 * transport it wants. Adding a default here would let a call site silently keep
 * plaintext after the broker has closed 5672.
 */
void
SetMqClientConfig(
    Configs& config,
    const bool ha,
    const std::string& ctrlIp,
    const std::string& pass,
    const std::string& clusterGroup,
    const bool ssl,
    const bool withRpcTimeout = true);

std::string
KafkaServers(
    const bool ha,
    const std::string& controller,
    const std::string& clusterGroup,
    bool quote = false);

std::string
StorPubIf(const std::string& storage);

std::string
StorClusterIf(const std::string& storage);

std::string
GetMgmtCidrIp(
    const std::string& mgmtCidr,
    int idx,
    const std::string& octet);

std::string
GetMgmtCidr(const std::string& mgmtCidr, int idx);

#endif /* endif CUBE_CLUSTER_H */
