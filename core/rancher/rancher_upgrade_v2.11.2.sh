#!/bin/bash

set -e

# Fetch the current Rancher settings
cat <<'EOF'
 ______   _       _        _____                  _                   _____      _   _   _                         
|  ____| | |     | |      |  __ \                | |                 / ____|    | | | | (_)                        
| |__ ___| |_ ___| |__    | |__) |__ _ _ __   ___| |__   ___ _ __   | (___   ___| |_| |_ _ _ __   __ _ ___         
|  __/ _ \ __/ __| '_ \   |  _  // _` | '_ \ / __| '_ \ / _ \ '__|   \___ \ / _ \ __| __| | '_ \ / _` / __|        
| | |  __/ || (__| | | |  | | \ \ (_| | | | | (__| | | |  __/ |      ____) |  __/ |_| |_| | | | | (_| \__ \  _ _ _ 
|_|  \___|\__\___|_| |_|  |_|  \_\__,_|_| |_|\___|_| |_|\___|_|     |_____/ \___|\__|\__|_|_| |_|\__, |___/ (_|_|_)
                                                                                                  __/ |            
                                                                                                 |___/             
EOF

REPLICAS=$(k3s kubectl get nodes -o go-template='{{len .items}}')
VALUES="
bootstrapPassword: admin
replicas: ${REPLICAS}
ingress:
  enabled: true
  pathType: ImplementationSpecific
  path: "/"
  tls:
    source: secret
tls: external
privateCA: true
useBundledSystemChart: true
antiAffinity: required
"

echo "current replicas: ${REPLICAS}"
echo "current values: ${VALUES}"


# Ugrade Rancher server to version 2.11.2
echo "------------------------------------------------------------------------------------------------------------------------------"
cat <<'EOF'

  _    _                           _         _____                  _                   _____                                    
 | |  | |                         | |       |  __ \                | |                 / ____|                                   
 | |  | |_ __   __ _ _ __ __ _  __| | ___   | |__) |__ _ _ __   ___| |__   ___ _ __   | (___   ___ _ ____   _____ _ __           
 | |  | | '_ \ / _` | '__/ _` |/ _` |/ _ \  |  _  // _` | '_ \ / __| '_ \ / _ \ '__|   \___ \ / _ \ '__\ \ / / _ \ '__|          
 | |__| | |_) | (_| | | | (_| | (_| |  __/  | | \ \ (_| | | | | (__| | | |  __/ |      ____) |  __/ |   \ V /  __/ |       _ _ _ 
  \____/| .__/ \__, |_|  \__,_|\__,_|\___|  |_|  \_\__,_|_| |_|\___|_| |_|\___|_|     |_____/ \___|_|    \_/ \___|_|      (_|_|_)
        | |     __/ |                                                                                                          
        |_|    |___/                                                                                                           

EOF

helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update
helm --kubeconfig /etc/rancher/k3s/k3s.yaml upgrade --install rancher rancher-stable/rancher --namespace cattle-system --version 2.11.2 --values <(echo "$VALUES")


# Upgrade Rancher CLI to version 2.11.2 and sync it to the other control nodes
echo "------------------------------------------------------------------------------------------------------------------------------"
cat <<'EOF'

  _    _                           _         _____                  _                   _____ _      _____           
 | |  | |                         | |       |  __ \                | |                 / ____| |    |_   _|          
 | |  | |_ __   __ _ _ __ __ _  __| | ___   | |__) |__ _ _ __   ___| |__   ___ _ __   | |    | |      | |            
 | |  | | '_ \ / _` | '__/ _` |/ _` |/ _ \  |  _  // _` | '_ \ / __| '_ \ / _ \ '__|  | |    | |      | |            
 | |__| | |_) | (_| | | | (_| | (_| |  __/  | | \ \ (_| | | | | (__| | | |  __/ |     | |____| |____ _| |_     _ _ _ 
  \____/| .__/ \__, |_|  \__,_|\__,_|\___|  |_|  \_\__,_|_| |_|\___|_| |_|\___|_|      \_____|______|_____|   (_|_|_)
        | |     __/ |                                                                                                
        |_|    |___/                                                                                                 

EOF

wget -qO- --no-check-certificate https://releases.rancher.com/cli2/v2.11.2/rancher-linux-amd64-v2.11.2.tar.gz | tar -xz --strip-components=2 -C /usr/local/bin/
cubectl node rsync -r control /usr/local/bin/rancher
