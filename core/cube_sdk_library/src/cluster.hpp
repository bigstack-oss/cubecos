// CUBE SDK

#ifndef CUBE_CLUSTER_H
#define CUBE_CLUSTER_H

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

#define GetController(isctrl, hostname, controller) (isctrl ? hostname : controller)

int GetControlWorkers(
    bool isConverged,
    bool isEdge);

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

std::string
RabbitMqServers(
    const bool ha,
    const std::string& ctrlIp,
    const std::string& pass,
    const std::string& clusterGroup);

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
