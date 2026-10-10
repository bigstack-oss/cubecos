// HEX SDK

#include <hex/config_module.h>

#include <hex/config_global.h>

#include <include/role_cubesys.h>

CONFIG_TUNING(NET_HOSTNAME, "net.hostname", TUNING_UNPUB, "Set appliance hostname.");

// private tunings
CONFIG_TUNING_STR(CUBESYS_ROLE, "cubesys.role", TUNING_UNPUB, "Set the role of cube appliance.", "undef", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_CONTROL_ADDRS, "cubesys.control.addrs", TUNING_UNPUB, "Set control group address [ip,ip,...].", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_BOOL(CUBESYS_HA, "cubesys.ha", TUNING_UNPUB, "Set true for indicate a HA setup.", false);

CONFIG_MODULE(net, NULL, NULL, NULL, NULL, NULL);
CONFIG_MODULE(cubesys, NULL, NULL, NULL, NULL, NULL);
CONFIG_MODULE(cube_scan, NULL, NULL, NULL, NULL, NULL);

// config_kafka takes these by CONFIG_GLOBAL_*_REF; the real definitions live in
// config_cube_scan.cpp, which is not linked into this test binary.
CONFIG_GLOBAL_BOOL(IS_MASTER)(false);
CONFIG_GLOBAL_STR(MGMT_ADDR)("10.99.99.98");
CONFIG_GLOBAL_STR(SHARED_ID)("10.99.99.99");
