// HEX SDK

#include <hex/config_module.h>

#include <hex/config_global.h>

#include <include/role_cubesys.h>
#include <constant.hpp>

const static char OPENSTACK_PASS[] = "39H4Heu1pEh1amat";
static const char ADMINCLIPASS[] = "66K1ogIiRt5KnyHe";

CONFIG_TUNING(NET_HOSTNAME, "net.hostname", TUNING_UNPUB, "Set appliance hostname.");

// external tunings
CONFIG_TUNING_STR(RABBITMQ_OPENSTACK_PASSWD, "rabbitmq.openstack.password", TUNING_UNPUB, "Set rabbitmq openstack password.", OPENSTACK_PASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_BOOL(RABBITMQ_SSL_ENABLED, "rabbitmq.ssl.enabled", TUNING_UNPUB, "Set to true to enable the AMQPS listener on 5671.", false);
CONFIG_TUNING_STR(CUBESYS_ROLE, "cubesys.role", TUNING_UNPUB, "Set the role of cube appliance.", "undef", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_DOMAIN, "cubesys.domain", TUNING_UNPUB, "Set the domain of cube appliance.", DOMAIN_DEF, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_REGION, "cubesys.region", TUNING_UNPUB, "Set the region of cube appliance.", REGION_DEF, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_SEED, "cubesys.seed", TUNING_UNPUB, "Set CubeCOS cluster secret seed.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_MGMT_CIDR, "cubesys.mgmt.cidr", TUNING_UNPUB, "Set CubeCOS cluster management CIDR.", MGMT_CIDR_DEF, ValidateIpRange, "");
CONFIG_TUNING_BOOL(CUBESYS_SALTKEY, "cubesys.saltkey", TUNING_UNPUB, "Set true for enabling key scrambling.", false);
CONFIG_TUNING_BOOL(CUBESYS_HA, "cubesys.ha", TUNING_UNPUB, "Set true for indicate a HA setup.", false);
CONFIG_TUNING_STR(CUBESYS_CONTROL_ADDRS, "cubesys.control.addrs", TUNING_UNPUB, "Set control group address [ip,ip,...].", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(KEYSTONE_ADMIN_CLI_PASS, "keystone.admin.cli.password", TUNING_UNPUB, "Set keystone admin cli password.", ADMINCLIPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CINDER_VOLUME_TYPE_DEFAULT, "cinder.storage.volumeType.default", TUNING_UNPUB, "Set the default cinder volume type.", BUILTIN_VOLUME_TYPE, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CINDER_STORAGE_BACKEND, "cinder.storage.backend.%d.name", TUNING_UNPUB, "Set additional storage backends.", "", ValidateRegex, DFT_REGEX_STR);

// cluster.cpp references GetIPAddr; keep the test independent of host interfaces.
bool
GetIPAddr(const char* ifname, char* ipaddr, int len, int af)
{
    snprintf(ipaddr, len, "%s", "10.99.99.98");
    return true;
}

CONFIG_MODULE(net, NULL, NULL, NULL, NULL, NULL);
CONFIG_MODULE(memcache, NULL, NULL, NULL, NULL, NULL);
CONFIG_MODULE(neutron, NULL, NULL, NULL, NULL, NULL);
CONFIG_MODULE(nova, NULL, NULL, NULL, NULL, NULL);
CONFIG_MODULE(cinder, NULL, NULL, NULL, NULL, NULL);
CONFIG_MODULE(rabbitmq, NULL, NULL, NULL, NULL, NULL);
CONFIG_MODULE(cubesys, NULL, NULL, NULL, NULL, NULL);
CONFIG_MODULE(keystone, NULL, NULL, NULL, NULL, NULL);

// config_manila takes these by CONFIG_GLOBAL_STR_REF; the real definitions live in
// config_cube_scan.cpp, which is not linked into this test binary.
CONFIG_GLOBAL_STR(MGMT_ADDR)("10.99.99.98");
CONFIG_GLOBAL_STR(SHARED_ID)("10.99.99.99");
CONFIG_GLOBAL_STR(EXTERNAL)("10.99.99.99");
