#!/usr/bin/env bash

set -e

# CONSTANTS

readonly KIND_NODE_IMAGE=kindest/node:v1.30.0
readonly DNSMASQ_DOMAIN=kind.cluster
readonly DNSMASQ_CONF=kind.k8s.conf

# FUNCTIONS

log(){
  echo "---------------------------------------------------------------------------------------"
  echo $1
  echo "---------------------------------------------------------------------------------------"
}

wait_ready(){
  local NAME=${1:-pods}
  local TIMEOUT=${2:-5m}
  local SELECTOR=${3:---all}

  log "WAIT $NAME ($TIMEOUT) ..."

  kubectl wait -A --timeout=$TIMEOUT --for=condition=ready $NAME $SELECTOR
}

wait_pods_ready(){
  local TIMEOUT=${1:-5m}

  wait_ready pods $TIMEOUT --field-selector=status.phase!=Succeeded
}

wait_nodes_ready(){
  local TIMEOUT=${1:-5m}

  wait_ready nodes $TIMEOUT
}

network(){
  local NAME=${1:-kind}

  log "NETWORK (kind) ..."

  if [ -z $(docker network ls --filter name=^$NAME$ --format="{{ .Name }}") ]
  then 
    docker network create $NAME
    echo "Network $NAME created"
  else
    echo "Network $NAME already exists, skipping"
  fi
}

get_service_lb_ip(){
  kubectl get svc -n $1 $2 -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
}

cluster(){
  local NAME=${1:-kind}

  log "CLUSTER ..."

  docker pull $KIND_NODE_IMAGE

  kind create cluster --name $NAME --image $KIND_NODE_IMAGE --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
kubeadmConfigPatches:
  - |-
    kind: ClusterConfiguration
    controllerManager:
      extraArgs:
        bind-address: 0.0.0.0
    etcd:
      local:
        extraArgs:
          listen-metrics-urls: http://0.0.0.0:2381
    scheduler:
      extraArgs:
        bind-address: 0.0.0.0
nodes:
  - role: control-plane
  - role: worker
  - role: worker
  - role: worker
EOF
}

metallb(){
  log "METALLB ..."

helm upgrade --install --wait --timeout 35m --atomic --namespace metallb-system --create-namespace \
    --repo https://metallb.github.io/metallb metallb metallb

LB_NET_PREFIX=$(docker network inspect -f '{{range .IPAM.Config }}{{ .Gateway }}{{end}}' kind | cut -d '.' -f1,2,3)
LB_NET_IP_FIRST=${LB_NET_PREFIX}.200
LB_NET_IP_LAST=${LB_NET_PREFIX}.250


kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - ${LB_NET_IP_FIRST}-${LB_NET_IP_LAST}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: layer2
  namespace: metallb-system
spec:
  ipAddressPools:
  - first-pool
EOF
}

ingress(){
  log "INGRESS-NGINX ..."

  helm upgrade --install --wait --timeout 35m --atomic --namespace ingress-nginx --create-namespace \
    --repo https://kubernetes.github.io/ingress-nginx ingress-nginx ingress-nginx --values - <<EOF
controller:
  extraArgs:
    update-status: "true"
EOF
}

dnsmasq(){
  log "Hosts ..."
  local INGRESS_LB_IP=$(get_service_lb_ip ingress-nginx ingress-nginx-controller)
  echo "$INGRESS_LB_IP grafana.kind.cluster alertmanager.kind.cluster agent.kind.cluster single.kind.cluster" | sudo tee -a /etc/hosts
}

cleanup(){
  log "CLEANUP ..."
  sudo sed -i '/single.kind.cluster$/d' /etc/hosts
  kind delete cluster || true
}

# RUN

cleanup
network
cluster
metallb
ingress
dnsmasq

# DONE

log "CLUSTER READY !"
