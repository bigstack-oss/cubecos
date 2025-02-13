k3s kubectl delete node $1 --timeout=60s || \
    k3s kubectl patch node $1 -p '{"metadata":{"finalizers":[]}}' --type=merge

# Clean up all PVCs
k3s kubectl get pvc -A -o go-template='{{range .items}}{{$node := index .metadata.annotations "volume.kubernetes.io/selected-node"}}{{if eq $node "'$1'"}}{{.metadata.name}}{{" --namespace="}}{{.metadata.namespace}}{{"\n"}}{{end}}{{end}}' | \
    xargs -L1 k3s kubectl delete --timeout=2m pvc
