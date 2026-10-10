// CUBE SDK

#include "upgrade.hpp"

bool IsRollingUpgrade()
{
    return (HexUtilSystemF(
                0,
                0,
                "%s is_cluster_rolling",
                HEX_SDK)
        == 0);
}

bool IsRollingRestartBoot()
{
    return (HexUtilSystemF(
                0,
                0,
                "%s is_rolling_restart_boot",
                HEX_SDK)
        == 0);
}
