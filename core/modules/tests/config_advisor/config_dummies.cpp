// HEX SDK

// config_advisor observes cubesys for the node's role, which binds it to the
// tuning spec config_cubesys.cpp defines. That module is not linked into this
// test binary -- only the module under test is -- so the spec is defined here,
// the way config_lachesis's test does it.

#include <hex/config_module.h>

CONFIG_TUNING_STR(CUBESYS_ROLE, "cubesys.role", TUNING_UNPUB, "Set the role of cube appliance.", "undef", ValidateRegex, DFT_REGEX_STR);

// The modules config_advisor names: cubesys, whose role it observes, and
// net_static, which it must run after.
CONFIG_MODULE(cubesys, NULL, NULL, NULL, NULL, NULL);
CONFIG_MODULE(net_static, NULL, NULL, NULL, NULL, NULL);
