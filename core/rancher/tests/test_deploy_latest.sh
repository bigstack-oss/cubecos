echo $TOP_BLDDIR

make test -C $TOP_BLDDIR/core/k3s

helm repo add rancher-latest https://releases.rancher.com/server-charts/latest

k3s kubectl create namespace cattle-system

k3s kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.5.1/cert-manager.crds.yaml

helm repo add jetstack https://charts.jetstack.io

helm repo update

helm --kubeconfig /etc/rancher/k3s/k3s.yaml install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.5.1

helm --kubeconfig /etc/rancher/k3s/k3s.yaml install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname=$(hostname -i).sslip.io \
  --set replicas=1 \
  --set bootstrapPassword=admin
