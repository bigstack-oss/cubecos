// CUBE SDK

#ifndef CUBE_UPGRADE_H
#define CUBE_UPGRADE_H

#include <hex/process.h>
#include <hex/process_util.h>

/**
 * Check if the node is under rolling upgrade.
 */
bool IsRollingUpgrade();

/**
 * Check if this boot is this node's own reboot in a running rolling restart.
 */
bool IsRollingRestartBoot();

#endif /* endif CUBE_UPGRADE_H */
