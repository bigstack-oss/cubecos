// CUBE SDK

#ifndef CUBE_NETWORK_H
#define CUBE_NETWORK_H

#include <string>
#include <sys/socket.h>

// Process extended API requires C++
#ifdef __cplusplus

// get parent interface
std::string GetParentIf(const std::string& ifname);

// ipaddr must be big enough to hold an IPv4/6 address.
bool GetIPAddr(const char* ifname, char* ipaddr, int len, int af);

// return x.x.x.x/x by giving interface name
std::string GetCIDRv4(std::string ifname);

#endif // __cplusplus

#endif /* endif CUBE_NETWORK_H */

