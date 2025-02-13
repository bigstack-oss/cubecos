#!/bin/sh

if [[ "$AMX_ANNOTATION_kubeconfig" ]]; then
    KUBECONFIG="$AMX_ANNOTATION_kubeconfig"
else
    KUBECONFIG=$(rancher cluster kf "$AMX_ANNOTATION_cluster" 2>/dev/null)
fi

echo "<Applying yaml>"
echo "$AMX_ANNOTATION_yaml"
echo
echo "<Using kubeconfig>"
echo "$KUBECONFIG"
echo
echo "<Result>"
echo "$AMX_ANNOTATION_yaml" | kubectl --insecure-skip-tls-verify --kubeconfig <(echo "$KUBECONFIG") apply -f -
