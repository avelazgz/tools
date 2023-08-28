#!/bin/bash

sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl git vim haproxy open-iscsi
curl -fsSLo containerd-config.toml https://gist.githubusercontent.com/oradwell/31ef858de3ca43addef68ff971f459c2/raw/5099df007eb717a11825c3890a0517892fa12dbf/containerd-config.toml
sudo mkdir /etc/containerd
sudo mv containerd-config.toml /etc/containerd/config.toml
wget https://github.com/containerd/containerd/releases/download/v1.7.3/containerd-1.7.3-linux-amd64.tar.gz
#tar xvf containerd-1.7.3-linux-amd64.tar.gz
sudo tar Cxzvf /usr/local containerd-1.7.3-linux-amd64.tar.gz
sudo curl -fsSLo /etc/systemd/system/containerd.service https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
sudo systemctl daemon-reload
sudo systemctl enable --now containerd
curl -fsSLo runc.amd64 https://github.com/opencontainers/runc/releases/download/v1.1.9/runc.amd64
sudo install -m 755 runc.amd64 /usr/local/sbin/runc
curl -fLo cni-plugins-linux-amd64-v1.1.2.tgz https://github.com/containernetworking/plugins/releases/download/v1.1.2/cni-plugins-linux-amd64-v1.1.2.tgz
sudo mkdir -p /opt/cni/bin
sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.1.2.tgz
curl -fLo cni-plugins-linux-amd64-v1.3.0.tgz https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz
sudo mkdir -p /opt/cni/bin
sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.3.0.tgz
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe -a overlay br_netfilter
# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
# Apply sysctl params without reboot
sudo sysctl --system
# Add Kubernetes GPG key
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
# Add Kubernetes apt repository
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo swapon --show
sudo swapoff -a
sudo sed -i -e '/swap/d' /etc/fstab
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | sudo bash
sudo systemctl enable --now iscsid
helm repo add openebs https://openebs.github.io/charts
kubectl create namespace openebs
helm --namespace=openebs install openebs openebs/openebs
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.1.1/deploy/static/provider/baremetal/deploy.yaml
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
export NODE_PORT_HTTP="$(kubectl get service/ingress-nginx-controller -n ingress-nginx -o go-template='{{(index .spec.ports 0).nodePort}}')"
export NODE_PORT_HTTPS="$(kubectl get service/ingress-nginx-controller -n ingress-nginx -o go-template='{{(index .spec.ports 1).nodePort}}')"

cat <<EOF | sudo tee /etc/haproxy/haproxy.cfg
global
        log /dev/log    local0
        log /dev/log    local1 notice
        chroot /var/lib/haproxy
        stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
        stats timeout 30s
        user haproxy
        group haproxy
        daemon

defaults
    mode tcp

frontend front_http
    bind :80
    default_backend back_http

backend back_http
    server http1 localhost:$NODE_PORT_HTTP

frontend front_https
    bind :443
    default_backend back_https

backend back_https
    server https1 localhost:$NODE_PORT_HTTPS
EOF
sudo systemctl restart haproxy

interface_names=$(ip -o link show | awk -F': ' '$2 ~ /^ens/ {print $2}')

for interface in $interface_names; do
    ip_address=$(ip -o -4 addr show dev $interface | awk '{split($4, a, "/"); print a[1]}')
    hex_ip=$(printf '%02X' $(echo $ip_address | tr '.' ' ') | tr 'A-F' 'a-f')
done

echo -e "\n\n\nPuedes llamar al ingress de este servidor mediante http://X.$hex_ip.nip.io\n"
