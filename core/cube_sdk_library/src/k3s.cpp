// CUBE SDK

#include "k3s.hpp"

bool IsK3sReady()
{
    const ExecSyncResult nr = ExecBashSync(
        0,
        false,
        false,
        {},
        "/usr/local/bin/k3s kubectl get nodes");
    if (nr.exitCode != 0) {
        return false;
    }

    const ExecSyncResult cr = ExecBashSync(
        0,
        false,
        false,
        {},
        "/usr/local/bin/k3s kubectl cluster-info");
    if (cr.exitCode != 0) {
        return false;
    }

    return true;
}

int K3sGetNodeCounts()
{
    const ExecSyncResult r = ExecBashSync(
        0,
        true,
        false,
        {}, "/usr/local/bin/k3s kubectl get nodes -o \"go-template={{len .items}}\"");
    if (r.exitCode != 0) {
        return -1;
    }

    int count = 0;
    try {
        std::size_t pos;
        count = std::stoi(r.stdoutOutput, &pos);
    } catch (const std::exception& e) {
        // failed to convert the output string to an integer
        return -1;
    }

    if (count < 0) {
        return 0;
    }

    return count;
}

bool K3sHasNamespace(const std::string appNamespace)
{
    const ExecSyncResult r = ExecBashSync(
        0,
        false,
        false,
        {},
        std::string()
            + "/usr/local/bin/k3s kubectl get namespace '"
            + appNamespace
            + "' -o name");
    return (r.exitCode == 0);
}

bool K3sCreateNamespace(const std::string appNamespace)
{
    if (K3sHasNamespace(appNamespace)) {
        return true;
    }

    const ExecSyncResult r = ExecBashSync(
        0,
        false,
        false,
        {},
        "/usr/local/bin/k3s kubectl create namespace '" + appNamespace + "'");
    return (r.exitCode == 0);
}

bool K3sDeleteNamespace(const std::string appNamespace)
{
    if (!K3sHasNamespace(appNamespace)) {
        return true;
    }

    return HexUtilSystemF(
               0,
               0,
               "/usr/local/bin/k3s kubectl delete namespace %s",
               appNamespace.c_str())
        == 0;
}

int K3sGetReadyReplicas(
    const std::string app,
    const std::string appNamespace)
{
    const ExecSyncResult r = ExecBashSync(
        0,
        true,
        false,
        {},
        std::string()
            + "/usr/local/bin/k3s kubectl "
            + "get " + app
            + " -n " + appNamespace + " "
            + "-o \"go-template={{.status.readyReplicas}}\"");
    if (r.exitCode != 0) {
        return -1;
    }

    int count = 0;
    try {
        std::size_t pos;
        count = std::stoi(r.stdoutOutput, &pos);
    } catch (const std::exception& e) {
        // failed to convert the output string to an integer
        return -1;
    }

    if (count < 0) {
        return 0;
    }

    return count;
}

bool K3sWatchRollOut(
    const std::string app,
    const std::string appNamespace,
    const std::string timeout)
{
    const ExecSyncResult r = ExecBashSync(
        0,
        false,
        false,
        {},
        std::string()
            + "/usr/local/bin/k3s kubectl rollout status "
            + "--timeout " + timeout + " " + app + " "
            + "-n " + appNamespace);
    return (r.exitCode == 0);
}

bool K3sDeleteAllPods(const std::string appNamespace)
{
    return HexUtilSystemF(
               0,
               0,
               "/usr/local/bin/k3s kubectl delete pods --all -n %s --grace-period=0 --force",
               appNamespace.c_str())
        == 0;
}
