#!/bin/sh

pushd /tmp >/dev/null 2>&1
timeout -k 1s 60s /usr/local/bin/terraform -chdir=/var/lib/terraform "$@"
[ $? -eq 0 ] || exit 1

if [ "$1" == "apply" ] || [ "$1" == "destroy" ] || [ "$1" == "import" ]; then
    /usr/local/bin/terraform -chdir=/var/lib/terraform state pull > /var/lib/terraform/terraform.tfstate

    if [ -f /etc/settings.cluster.json ]; then
        cubectl node rsync --role=control /var/lib/terraform/
    fi
fi
popd >/dev/null 2>&1 || true
