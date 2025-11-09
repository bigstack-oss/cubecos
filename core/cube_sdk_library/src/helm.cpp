// CUBE SDK

#include "helm.hpp"

bool ExecHelm(
    const std::string command,
    const std::string releaseName,
    const std::string appNamespace)
{
    return HexUtilSystemF(
               0,
               0,
               "/usr/local/bin/helm --kubeconfig=/etc/rancher/k3s/k3s.yaml %s %s -n %s",
               command.c_str(),
               releaseName.c_str(),
               appNamespace.c_str())
        == 0;
}
