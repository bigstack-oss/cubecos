// CUBE SDK

// config_gpu declares no CONFIG_TUNINGs and calls into no other config module -
// it talks to nvidia-smi, sriov-manage, hex_sdk and its own truth file, and
// nothing else. So unlike the other module tests here there is nothing to stub
// out; this file exists to keep the hex_config_MODULES shape the harness
// expects.

#include <hex/config_module.h>
