// CUBE SDK

#include "k3s.hpp"

int K3sGetNodeCounts()
{
    std::string output = HexUtilPOpen(
        "/usr/local/bin/k3s kubectl "
        "get nodes "
        "-o \"go-template={{len .items}}\"");

    int count = 0;
    try {
        std::size_t pos;
        count = std::stoi(output, &pos);
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
    return HexUtilSystemF(
               0,
               0,
               "/usr/local/bin/k3s kubectl get namespace %s -o name",
               appNamespace.c_str())
        == 0;
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
    std::string output = HexUtilPOpen(
        "/usr/local/bin/k3s kubectl "
        "get %s -n %s "
        "-o \"go-template={{.status.readyReplicas}}\"",
        app.c_str(),
        appNamespace.c_str());

    int count = 0;
    try {
        std::size_t pos;
        count = std::stoi(output, &pos);
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
    return HexUtilSystemF(
               0,
               0,
               "/usr/local/bin/k3s kubectl rollout status --timeout %s %s -n %s",
               timeout.c_str(),
               app.c_str(),
               appNamespace.c_str())
        == 0;
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
