// CUBE SDK

#ifndef CUBE_K3S_H
#define CUBE_K3S_H

#include <hex/process_util.h>

#include <string>

/**
 * Get the number of K3S node.
 * Return -1, if the output is not an integer.
 */
int K3sGetNodeCounts();

/**
 * Get the number of ready replicas.
 * Return -1, if the output is not an integer.
 */
int K3sGetReadyReplicas(
    const std::string app,
    const std::string appNamespace);

/**
 * Check if the app pods are all rolled out.
 */
bool K3sWatchRollOut(
    const std::string app,
    const std::string appNamespace,
    const std::string timeout);

/**
 * Delete all pods within a namespace.
 */
bool K3sDeleteAllPods(const std::string appNamespace);

#endif /* endif CUBE_K3S_H */
