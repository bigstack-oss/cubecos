// CUBE SDK

#ifndef OPENSTACK_ENDPOINT_H
#define OPENSTACK_ENDPOINT_H

// Process extended API requires C++
#ifdef __cplusplus

#include <openstack/common.h>

enum OpenStackEndpoitnE {
    BAD_SERVICE_NAME = 0x1,
    ENV_NOT_INIT = 0x2,
    NONE_MULTIPLE_MATCH = 0x4,
    FAIL_GET_EID = 0x8,
    FAIL_DEL_EP = 0x10,
    FAIL_CREATE_EP = 0x20,
};

// Get Openstack endpoint id by service name
void OpenstackEndpointIdByServer(const char* srv, std::string &id);

// Create an Openstack endpoint
void OpenstackEndpointCreate(const char* srv, const char* rgn, const char* pub, const char* adm, const char* intr);

// Recreate an Openstack endpoint if settings changed
void OpenstackEndpointRecreate(const char* srv, const char* rgn, const char* pub, const char* adm, const char* intr);

#endif // __cplusplus

#endif /* endif OPENSTACK_ENDPOINT_H */

