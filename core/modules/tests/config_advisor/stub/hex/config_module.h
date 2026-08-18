// Minimal stand-in for hex/config_module.h. The registration macros become
// plain function pointers the driver can call, which is all the logic test
// needs; the real registration path is covered by test_config_advisor_01.sh
// against a properly linked hex_config.
#pragma once
#define CONFIG_MODULE(a, b, c, d, e, f)
#define CONFIG_COMMAND(name, mainf, usagef) int (*g_##name)(int, char **) = mainf;
