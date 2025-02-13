// CUBE SDK

#include <vector>

#include <hex/log.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/string_util.h>

#include <openstack/endpoint.h>

extern char* s_env;
extern const char* s_openstack;

void
OpenstackEndpointIdByServer(const char* srv, std::string &id)
{
    if (!srv)
        throw ENDPOINT_E(BAD_SERVICE_NAME);

    if (!s_env)
        throw ENDPOINT_E(ENV_NOT_INIT);

    std::string out;
    int rc;

    if (!HexRunCommand(rc, out, "/bin/sh -c '%s %s endpoint list -f value | grep %s'", s_env, s_openstack, srv))
        throw ENDPOINT_E(FAIL_GET_EID);

    std::vector<std::string> lines = hex_string_util::split(out, '\n');

    if (lines.size() != 1)
        throw ENDPOINT_E(NONE_MULTIPLE_MATCH);

    // the first column is ID
    id = hex_string_util::split(out, ' ')[0];
}

void
OpenstackEndpointCreate(const char* srv, const char* rgn, const char* pub, const char* adm, const char* intr)
{
    if (!srv)
        throw ENDPOINT_E(BAD_SERVICE_NAME);

    if (!s_env)
        throw ENDPOINT_E(ENV_NOT_INIT);

    if (HexUtilSystemF(0, 0, "%s %s endpoint create --region %s %s public %s",
                                s_env, s_openstack, rgn, srv, pub) != 0)
        throw ENDPOINT_E(FAIL_CREATE_EP);
    if (HexUtilSystemF(0, 0, "%s %s endpoint create --region %s %s admin %s",
                                s_env, s_openstack, rgn, srv, adm) != 0)
        throw ENDPOINT_E(FAIL_CREATE_EP);
    if (HexUtilSystemF(0, 0, "%s %s endpoint create --region %s %s internal %s",
                                s_env, s_openstack, rgn, srv, intr) != 0)
        throw ENDPOINT_E(FAIL_CREATE_EP);
}

void
OpenstackEndpointRecreate(const char* srv, const char* rgn, const char* pub, const char* adm, const char* intr)
{
    std::string id;
    OpenstackEndpointIdByServer(srv, id);

    if (HexUtilSystemF(0, 0, "%s %s endpoint delete %s", s_env, s_openstack, id.c_str()) != 0)
        throw ENDPOINT_E(FAIL_DEL_EP);

    OpenstackEndpointCreate(srv, rgn, pub, adm, intr);
}

