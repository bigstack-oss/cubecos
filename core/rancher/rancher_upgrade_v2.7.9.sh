#!/bin/bash

helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update
helm --kubeconfig /etc/rancher/k3s/k3s.yaml upgrade --install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --version 2.7.9 \
  --reuse-values

wget -qO- --no-check-certificate https://releases.rancher.com/cli2/v2.7.7/rancher-linux-amd64-v2.7.7.tar.gz | tar -xz --strip-components=2 -C /usr/local/bin/
cubectl node rsync -r control /usr/local/bin/rancher
