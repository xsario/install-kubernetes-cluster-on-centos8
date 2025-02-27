#!/bin/bash
clear
###################################################
# define all varibles here
#
 master_node=master
 master_node_hostname=master-node
 master_node_ip=192.168.111.140

 worker_node1=worker-1
 worker_node1_hostname=worker-node1
 worker_node1_ip=192.168.111.141

 worker_node2=worker-2
 worker_node2_hostname=worker-node2
 worker_node2_ip=192.168.111.142
#
###################################################
echo -e "\033[1m----------Installation Starts Here----------------------------\033[0m"
echo
###################################################
# Change Hostname
#
echo -e "\033[1m----------Changing Hostname-----------------------------------\033[0m"
sudo hostnamectl set-hostname $master_node_hostname
echo "Hostname:" $(hostname)
echo
#
###################################################
# Deleting previous hosts entries if any
#
echo -e "\033[1m----------Updaing /etc/hosts file Phase-1---------------------\033[0m"

if grep -q "$master_node_ip.*$master_node_hostname" /etc/hosts; then sed -i "/$master_node_ip.*$master_node_hostname/d" /etc/hosts
else
        echo "No old entry found against $master_node with IP Address $master_node_ip"
fi

if grep -q "$worker_node1_ip.*$worker_node1_hostname" /etc/hosts; then sed -i "/$worker_node1_ip.*$worker_node1_hostname/d" /etc/hosts
else
        echo "No old entry found against $worker_node1 with IP Address $worker_node1_ip"
fi

if grep -q "$worker_node2_ip.*$worker_node2_hostname" /etc/hosts; then sed -i "/$worker_node2_ip.*$worker_node2_hostname/d" /etc/hosts
else
        echo "No old entry found against $worker_node2 with IP Address $worker_node2_ip"
fi

echo "Completed"
echo
###################################################
# Adding newlines to /etc/hosts
#
echo -e "\033[1m----------Updating /etc/hosts Phase-2-------------------------\033[0m"
cat <<EOF>> /etc/hosts
$master_node_ip $master_node $master_node_hostname
$worker_node1_ip $worker_node1 $worker_node1_hostname
$worker_node2_ip $worker_node2 $worker_node2_hostname
EOF

echo "Completed"
echo
echo -e "\033[1m----------Updated /etc/hosts file-----------------------------\033[0m"
echo "{"
cat /etc/hosts
echo "}"
echo
#
###################################################
# Disable SELinux enforcement
#
echo -e "\033[1m----------Disable SELinux-------------------------------------\033[0m"
setenforce 0 >/dev/null 2>&1
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
echo "Completed"
echo
#
###################################################
# Disable Firewall
#
echo -e "\033[1m----------Updating Firewall-----------------------------------\033[0m"
systemctl disable firewalld
systemctl stop firewalld

modprobe br_netfilter
echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables

# load new rules
sysctl --system >/dev/null 2>&1

echo "Completed"
echo
#
##################################################
#Disable Memory Swap
#
echo -e "\033[1m----------Disable Memory Swap---------------------------------\033[0m"
swapoff -a
echo "Completed"
echo
#
##################################################
# Deleting Previous Versions If Installed
#
echo -e "\033[1m----------Deleting Previous Installation----------------------\033[0m"
echo "0%"
sudo dnf remove -y docker \
        docker-client \
        docker-client-latest \
        docker-common \
        docker-latest \
        docker-latest-logrotate \
        docker-logrotate \
        docker-engine \
        >/dev/null 2>&1
echo "10%"

sudo rm -rf /var/lib/docker
sudo rm -rf /etc/docker
echo "20%"

if [ -d "/var/lib/kubelet" ]; then
  find /var/lib/kubelet | xargs -n 1 findmnt -n -t tmpfs -o TARGET -T | uniq | xargs -r umount -v  >/dev/null 2>&1
  sudo sudo rm -r -f /etc/kubernetes /var/lib/kubelet /var/lib/etcd >/dev/null 2>&1
else
  echo "40%"
fi

iptables --flush

sudo rm -rf ~/.kube
sudo rm -rf /etc/kubernetes

sudo rm -rf /etc/yum.repos.d/kubernetes.repo
sudo rm -rf /var/lib/etcd/
sudo rm -rf /var/lib/kubelet
sudo rm -rf /etc/kubernetes
echo "60%"

sudo dnf remove -y  kubelet kubeadm kubectl >/dev/null 2>&1
echo "80%"

sudo dnf remove -y  podman runc >/dev/null 2>&1
echo "100%"

echo "Completed"
echo
#
###################################################
# Upgrading
echo -e "\033[1m----------Upgrading-------------------------------------------\033[0m"
dnf -y upgrade >/dev/null 2>&1
echo "Completed"
echo
#
####################################################
# Installing Pre-requisites
#
echo -e "\033[1m----------Installing Pre-requisites---------------------------\033[0m"
echo "0%"
sudo dnf install -y yum-utils >/dev/null 2>&1
echo "10%"

sudo dnf config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo \
    >/dev/null 2>&1
echo "20%"

sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
echo "40%"

sudo systemctl enable docker >/dev/null 2>&1
echo "60%"
sleep 10

sudo systemctl start docker >/dev/null 2>&1
echo "80%"

docker_status=$(sudo systemctl is-active docker)

if [ $docker_status == "active" ]; then
        echo "100%"
else
        exit
fi

echo "Completed"
echo
#
###################################################
# Installing Kubernetes
#
echo -e "\033[1m----------Installing Kubernetes-------------------------------\033[0m"
echo "0%"

cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey = https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

echo "25%"

dnf upgrade -y >/dev/null 2>&1

echo "50%"

dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes >/dev/null 2>&1

echo "75%"
echo "100%"
echo "Completed"
echo
#
###################################################
# Restarting Containerd
#
echo -e "\033[1m----------Restarting Containerd-------------------------------\033[0m"
rm -rf /etc/containerd/config.toml
systemctl restart containerd
echo "Completed"
echo
#
###################################################
# Checking for Ports
#
echo -e "\033[1m----------Checking TCP Ports ---------------------------------\033[0m"

kube_api_server=6443
kubelet_api=10250
kube_scheduler=10259
kube_c_m=10257
etcd1=2379
etcd2=2380

#----------------------------------
if lsof -i:$kube_api_server > /dev/null; then
  # Get the process ID (PID) using the port
  pid=$(lsof -i:$kube_api_server -t)

  # Kill the process
  kill $pid

  echo "Process $pid using port $kube_api_server has been killed."
else
  echo "Port $kube_api_server is not open."
fi
#----------------------------------
if lsof -i:$kubelet_api > /dev/null; then
  # Get the process ID (PID) using the port
  pid=$(lsof -i:$kubelet_api -t)

  # Kill the process
  kill $pid

  echo "Process $pid using port $kubelet_api has been killed."
else
  echo "Port $kubelet_api is not open."
fi
#----------------------------------
if lsof -i:$kube_scheduler > /dev/null; then
  # Get the process ID (PID) using the port
  pid=$(lsof -i:$kube_scheduler -t)

  # Kill the process
  kill $pid

  echo "Process $pid using port $kube_scheduler has been killed."
else
  echo "Port $kube_scheduler is not open."
fi
#----------------------------------
echo
#
###################################################
# Initialing K8s Cluster
#
echo -e "\033[1m----------Configuring K8s Cluster using kubeadm---------------\033[0m"
kubeadm config images pull >/dev/null 2>&1
echo "Initializing kubeadm"
kubeadm init --pod-network-cidr 172.20.0.0/16 >$HOME/kubeadm-init.log

sleep 25

kubelet_status=$(sudo systemctl is-active kubelet)

if [ $kubelet_status == "active" ]; then
        mkdir -p $HOME/.kube
        sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
        sudo chown $(id -u):$(id -g) $HOME/.kube/config
else
        echo "There is some error during kubeadm init. Check /dev/kubectl-init.log"
        exit
fi

echo
#
###################################################
# Installation Completion
#
echo -e "\033[1m----------Installation Completed------------------------------\033[0m"
echo -e "\033[31m You can find log file in \"$HOME/kubeadm-init.log\" \033[0m"
echo
echo -e "\033[31m You can join any worker node by using below command: \033[0m"
tail -2 $HOME/kubeadm-init.log
echo
echo -e "\033[31m Here is the output of \"kubectl get nodes\" \033[0m"
kubectl get nodes
#
###################################################
echo -e "\033[1m--------------------------------------------------------------\033[0m"
