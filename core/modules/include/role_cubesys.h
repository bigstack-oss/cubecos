// CUBE SDK

#ifndef CUBESYS_H
#define CUBESYS_H

#define CUBE_MIGRATE    "/run/cube_migration"
#define CONTROL_REJOIN   "/run/control_rejoin"

#define DOMAIN_DEF  "default"
#define REGION_DEF  "RegionOne"
#define MGMT_CIDR_DEF  "10.254.0.0/16"

typedef enum {
    ROLE_UNDEF = 0x0,
    ROLE_CONTROL = 0x1,
    ROLE_NETWORK = 0x2,
    ROLE_COMPUTE = 0x4,
    ROLE_STORAGE = 0x8,
    ROLE_EDGE = 0x10,
    ROLE_CONTROL_NETWORK = ROLE_CONTROL | ROLE_NETWORK,
    ROLE_CONTROL_CONVERGED = ROLE_CONTROL | ROLE_NETWORK | ROLE_COMPUTE | ROLE_STORAGE,
    ROLE_CORE = ROLE_EDGE | ROLE_CONTROL | ROLE_NETWORK | ROLE_COMPUTE | ROLE_STORAGE,
    ROLE_MODERATOR = ROLE_EDGE | ROLE_CONTROL,
} CubeRole_e;

// cubesys configuration
struct CubeSysConfig
{
    std::string role;
    std::string domain;
    std::string region;
    std::string controller;
    std::string controllerIp;
    std::string external;
    std::string mgmt;
    std::string provider;
    std::string overlay;
    std::string storage;
    std::string seed;
    std::string mgmtCidr;
    std::string controlVip;
    std::string controlHosts;
    std::string controlAddrs;
    std::string storageHosts;
    std::string storageAddrs;
    bool ha;
    bool saltkey;

    CubeSysConfig(): ha(false), saltkey(false) {}
};

inline static CubeRole_e GetCubeRole(std::string s_role)
{
    if (s_role == "control") return ROLE_CONTROL;
    else if (s_role == "network") return ROLE_NETWORK;
    else if (s_role == "compute") return ROLE_COMPUTE;
    else if (s_role == "storage") return ROLE_STORAGE;
    else if (s_role == "control-network") return ROLE_CONTROL_NETWORK;
    else if (s_role == "control-converged") return ROLE_CONTROL_CONVERGED;
    else if (s_role == "edge-core") return ROLE_CORE;
    else if (s_role == "moderator") return ROLE_MODERATOR;
    else return ROLE_UNDEF;
}

#define IsControl(r)     (r & ROLE_CONTROL)
#define IsNetwork(r)     (r & ROLE_NETWORK)
#define IsCompute(r)     (r & ROLE_COMPUTE)
#define IsStorage(r)     (r & ROLE_STORAGE)
#define IsEdge(r)        (r & ROLE_EDGE)
#define IsConverged(r)   (r == ROLE_CONTROL_CONVERGED)
#define IsCore(r)        (r == ROLE_CORE)
#define IsModerator(r)   (r == ROLE_MODERATOR)

#define IsUndef(r)       (r == ROLE_UNDEF)

#define ControlReq(r)    ((r != ROLE_UNDEF) && !(r & ROLE_CONTROL))

#define IfMgmtReq(r)     (r != ROLE_UNDEF)
#define IfProviderReq(r) (IsCompute(r))
#define IfOverlayReq(r)  (IsCompute(r))
#define IfStorageReq(r)  (IsControl(r) || IsCompute(r) || IsStorage(r))

#define ControlVcpuReserved  4          /* 4 cores is considered minimum for running a control node */
#define ControlMemoryReservedMib  16384 /* 16 GB is considered minimum for running a control node */

#endif /* endif CUBESYS_H */

