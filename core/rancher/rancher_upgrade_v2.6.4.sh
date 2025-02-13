#!/bin/bash

REPLICAS=$(k3s kubectl get nodes -o go-template='{{len .items}}')
VALUES="
bootstrapPassword: admin
replicas: $REPLICAS
ingress:
  enabled: true
  tls:
    source: secret
tls: external
privateCA: true
useBundledSystemChart: true
antiAffinity: required
"

k3s kubectl delete -n cattle-system -R -f /opt/manifests/rancher/

helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update
helm --kubeconfig /etc/rancher/k3s/k3s.yaml upgrade --install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --version 2.6.4 \
  --values <(echo "$VALUES")

wget -qO- --no-check-certificate https://releases.rancher.com/cli2/v2.6.4/rancher-linux-amd64-v2.6.4.tar.gz | tar -xz --strip-components=2 -C /usr/local/bin/
cubectl node rsync -r control /usr/local/bin/rancher
