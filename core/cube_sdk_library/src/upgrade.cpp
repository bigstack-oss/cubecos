// CUBE SDK

#include "upgrade.hpp"

bool IsRollingUpgrade()
{
    return (HexUtilSystemF(
                0,
                0,
                "%s is_node_rolling_upgrade",
                HEX_SDK)
        == 0);
}
