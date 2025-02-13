// CUBE SDK

#ifndef CUBE_CLUSTER_H
#define CUBE_CLUSTER_H

#include <string>
#include <sys/socket.h>

// Process extended API requires C++
#ifdef __cplusplus

#define GetController(isctrl, hostname, controller) (isctrl ? hostname : controller)
bool IsMaster(bool isCtrl, const std::string& hostname, const std::string& clusterHosts);
size_t GetClusterSize(bool ha, const std::string& clusterGroup);
int GetControlWorkers(bool isConverged, bool isEdge);
std::string GetSaltKey(bool saltkey, const std::string& key, const std::string& salt);
std::string GetSaltBytesInBase64(bool saltkey, const int len, const std::string& key, const std::string& salt);
std::string GetControlId(bool isCtrl, std::string hostname, std::string controller);
std::string GetSharedId(bool isCtrl, bool ha, const std::string& ctrl, const std::string& ctrlVid);
std::string GetIfAddr(std::string ifname);
std::string GetControllerIp(bool isCtrl, std::string controllerIp, std::string mgmtIf);
std::string GetMaster(const std::string& clusterGroup);
std::string GetMaster(const bool ha, const std::string& controller, const std::string& controlGroup);
std::string MemcachedServers(const bool ha, const std::string& controller, const std::string& clusterGroup);
std::string RabbitMqServers(const bool ha, const std::string& ctrlIp, const std::string& pass, const std::string& clusterGroup);
std::string KafkaServers(const bool ha, const std::string& controller, const std::string& clusterGroup, bool quote = false);
std::vector<std::string> GetControllerPeers(const std::string& self, const std::string& controlGroup);
std::string StorPubIf(const std::string& storage);
std::string StorClusterIf(const std::string& storage);
std::string GetMgmtCidr(const std::string& mgmtCidr, int idx);
std::string GetMgmtCidrIp(const std::string& mgmtCidr, int idx, const std::string& octet);

#endif // __cplusplus

#endif /* endif CUBE_CLUSTER_H */


