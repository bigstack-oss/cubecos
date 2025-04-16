#!/bin/bash

if [ -z $KUBECONFIG ]
then
    echo "Please specify KUBECONFIG"
    exit 1
fi

CHARTS=(docker-registry chartmuseum keycloak harbor)
CHART_FOR_MULTI_DOMAINS=(ingress-nginx harbor)
DOMAINS=""

get_particular_chart_flags() {
    chart="${1}"
    flags=""

    case ${chart} in
        harbor)
            flags="--set expose.ingress.className=nginx-${domain}"
            ;;
        ingress-nginx)
            flags="--set controller.ingressClassResource.name=nginx-${domain}"
            flags+=" "
            flags+="--set controller.ingressClassResource.controllerValue=k8s.io/ingress-nginx-${domain}"
            ;;
        *)
            ;;
    esac
    
    echo ${flags}
}

deploy_chart_by_domains() {
    chart="${1}"

    for domain in "${DOMAINS[@]}"
    do
        flags=$(get_particular_chart_flags ${chart})
        eval helm --kubeconfig ${KUBECONFIG} --kube-insecure-skip-tls-verify=true upgrade --install ${chart}-${domain} ${flags} charts/${chart}/${chart}*.tgz -n ${chart}-${domain} --create-namespace --wait --wait-for-jobs -f charts/${chart}/${chart}-values.yaml --debug
    done
}

deploy_particular_chart_by_specified_domains() {
    for chart in "${CHART_FOR_MULTI_DOMAINS[@]}"
    do
        deploy_chart_by_domains "${chart}"
    done
}

deploy_particular_chart_if_multidomain_is_enabled() {
    if [[ "${#DOMAINS[@]}" -ge 1 ]];
    then
        deploy_particular_chart_by_specified_domains
    fi
}

deploy_default_chart() {
    for chart in "${CHARTS[@]}"
    do
        helm --kubeconfig ${KUBECONFIG} --kube-insecure-skip-tls-verify=true upgrade \
            --install ${chart} charts/${chart}/${chart}-*.tgz \
            -n ${chart} \
            --create-namespace \
            --wait \
            --wait-for-jobs \
            -f charts/${chart}/${chart}-values.yaml
    done
}

install() {
    while getopts "d:" opt; do
        case "$opt" in
            d)
                DOMAINS="${OPTARG}"
                ;;
            \?)
                echo "Usage: $0 [-d <domains with comma separated like 'domain-1,domain-2, ... '>]"
                exit 1
                ;;
        esac
    done
    IFS=','
    read -ra DOMAINS <<< "${DOMAINS}"

    deploy_default_chart

    deploy_particular_chart_if_multidomain_is_enabled
}

uninstall() {
    for chart in "${CHARTS[@]}"
    do
        helm --kubeconfig $KUBECONFIG --kube-insecure-skip-tls-verify=true uninstall $chart -n $chart
    done
}

$*
