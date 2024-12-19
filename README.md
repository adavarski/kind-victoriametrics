## Use Victoria metrics k8s stack as replacement for kube-prometheus-k8s stack

## Requirements

- docker
- kubectl
- kind cli
- helm

## Setup docker

```
$ cat /etc/docker/daemon.json 
{
  "default-address-pools": [
    {"base": "172.17.0.0/16", "size": 24}
  ]
}

Note: The above configuration sets up a single address pool of 172.17.0.0/16 affording over 65,000 IP addresses. Each network created within this pool will use a /24 CIDR subnet mask effectively providing 254 usable IP addresses.

$ docker network rm kind
$ sudo service docker restart

```

## Setup kubernetes cluster

Run `./cluster-setup.sh` and you got 1 control-plane nodes and 3 worker nodes kubernetes cluster with installed ingress-nginx, metallb and 4 proxy image repository in docker containers in one network

## Deploy Victoria Metrics stack

Run `./setup-vms.sh`

## Get grafana password

Login - admin

Password:

`kubectl get secret --namespace victoria-metrics vm-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo`

## Open web UI

- [Grafana](http://grafana.kind.cluster)

<img src="pictures/grafana-victoriametrics-datasourece.png?raw=true" width="1000">

<img src="pictures/grafana-victoriametrics.png?raw=true" width="1000">


- [Alertmanager](http://alertmanager.kind.cluster)
- [VMagent](http://agent.kind.cluster)
- [VMsingle](http://single.kind.cluster)
