// CUBE SDK

#include "cli_iaas.hpp"

// This mode is not available in STRICT error state
CLI_MODE(
    CLI_TOP_MODE,
    CLI_TOP_COMMAND_IAAS,
    "Work with IaaS settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());
