// CUBE SDK

#include <errno.h>
#include <ifaddrs.h> // getifaddrs()
#include <net/if.h> // IFF_UP
#include <arpa/inet.h> // inet_ntop()

#include <string>

#include <hex/log.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/string_util.h>

std::string
GetParentIf(const std::string& ifname)
{
    std::string current, master;

    current = master = ifname;
    do {
        // FIXME: is there a way to get upper ifname with POSIX interface?
        std::string pIfs = HexUtilPOpen(HEX_SDK " GetParentIfname %s", current.c_str());
        if (pIfs.length() > 0) {
            // find valid master
            auto pIfv = hex_string_util::split(pIfs, '\n');
            for (size_t i = 0 ; i < pIfv.size() ; i++) {
                std::string pIf = pIfv[i];
                if (pIf.length() > 0 && strchr(pIf.c_str(), '.') == NULL /* pif is not vlan interface */) {
                    if (pIf[pIf.length() - 1] == '\n')
                        pIf[pIf.length() - 1] = '\0';
                    master = pIf;
                }
            }
            // no change
            if (current == master)
                return current;
            else
                current = master;
        }
        else
            break;
    } while (1);

    return current;
}

bool
GetIPAddr(const char* ifname, char* ipaddr, int len, int af)
{
    std::string pIf;
    struct ifaddrs *addrs, *ifa;

    pIf = GetParentIf(ifname);

    // Get the list of our IP addresses.
    int ret = getifaddrs(&addrs);
    if (ret != 0) {
        HexLogWarning("cannot retrieve the IP addresses of the appliance, errno=%d", errno);
        return false;
    }

    // Scroll through each of our interfaces, looking for a match the given ifname
    for (ifa = addrs; ifa != NULL; ifa = ifa->ifa_next) {

        // Is this a valid interface?
        if (ifa->ifa_addr == NULL)
            continue;

        // Is the interface up?
        if ((ifa->ifa_flags & IFF_UP) == 0)
            continue;

        // Does the interface name match?
        if (strcmp(ifa->ifa_name, pIf.c_str()) != 0)
            continue;

        // Does the address family match?
        if (ifa->ifa_addr->sa_family != af)
            continue;

        if (af == AF_INET) {
            struct sockaddr_in* s4 = (struct sockaddr_in *)(ifa->ifa_addr);
            if (inet_ntop(ifa->ifa_addr->sa_family,
                (void *)&(s4->sin_addr), ipaddr, len) == NULL) {
                HexLogWarning("inet_ntop() failed for ipv4 address");
                continue;
            }

            break;
        }
        else if (af == AF_INET6) {
            struct sockaddr_in6 *s6 = (struct sockaddr_in6 *)(ifa->ifa_addr);
            if (inet_ntop(ifa->ifa_addr->sa_family,
                (void *)&(s6->sin6_addr), ipaddr, len) == NULL) {
                HexLogWarning("inet_ntop() failed for ipv6 address");
                continue;
            }

            break;
        }
    }
    if (addrs)
        freeifaddrs(addrs);

    return true;
}

static int
Mask2Prefix(const struct in_addr &addr)
{
    unsigned int uaddr = htonl(addr.s_addr);
    unsigned int bitmask = 0xffffffff;
    // Loop over all the CIDR prefixes and check if the address is equal
    // to any of them.
    for (int idx = 0; idx <= 32; ++idx) {
        if ((0xffffffff & ~bitmask) == uaddr) {
            return idx;
        }
        bitmask >>= 1;
    }
    return 0;
}

/* return x.x.x.x/x by giving interface name */
std::string
GetCIDRv4(std::string ifname)
{
    std::string pIf;
    struct ifaddrs *addrs, *ifa;
    char cidr[128] = {0};

    snprintf(cidr, sizeof(cidr), "0.0.0.0/0");
    pIf = GetParentIf(ifname);

    // Get the list of structures describing
    // the network interfaces of the local system
    int ret = getifaddrs(&addrs);
    if (ret != 0) {
        HexLogWarning("cannot retrieve the network information of the appliance, errno=%d", errno);
        return "0.0.0.0/0";
    }

    // Scroll through each of our interfaces, looking for a match the given ifname
    for (ifa = addrs; ifa != NULL; ifa = ifa->ifa_next) {

        // Is this a valid interface?
        if (ifa->ifa_addr == NULL)
            continue;

        // Is the interface up?
        if ((ifa->ifa_flags & IFF_UP) == 0)
            continue;

        // Does the interface name match?
        if (strcmp(ifa->ifa_name, pIf.c_str()) != 0)
            continue;

        // Does the address family match?
        if (ifa->ifa_addr->sa_family != AF_INET)
            continue;

        struct sockaddr_in* s4 = (struct sockaddr_in *)(ifa->ifa_addr);
        struct sockaddr_in* m4 = (struct sockaddr_in *)(ifa->ifa_netmask);
        struct in_addr* v4addr = &s4->sin_addr;
        struct in_addr* v4netmask = &m4->sin_addr;
        struct in_addr network;

        network.s_addr = v4addr->s_addr & v4netmask->s_addr;
        int prefix = Mask2Prefix(*v4netmask);

        char nid[64] = {0};
        if (inet_ntop(AF_INET, (void *)&network, nid, sizeof(nid)) == NULL) {
            HexLogWarning("inet_ntop() failed for ipv4 address");
            return "0.0.0.0/0";
        }

        snprintf(cidr, sizeof(cidr), "%s/%d", nid, prefix);
        break;
    }

    if (addrs)
        freeifaddrs(addrs);

    return cidr;
}

