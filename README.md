This demonstrates using openssl to easily generate certificates for an etcd cluster.

```
Usage: kubessl.sh [-m mode] [-c file] [-t file] [-d int] [-h]

    -m value        Mode for sign certificate. e.g. 
                      init    [out: ca, sa, apiserver ...],
                      renew   [in: k8s-conf, openssl-cnf out: k8s-conf (replace)],
                      kubelet [in & out: kubelet-client-current.pem]
    -c file         Path to kubernetes configuration file (k8s-conf).
                    e.g. /etc/kubernetes/controller-manager.conf
    -t file         Path to openssl template file (openssl-cnf). 
                    e.g. /etc/kubernetes/cnf/controller-manager.cnf
    -d int          How long till expiry of a signed certificate - def 3650 days
    -h              Help

For Example:
    kubessl.sh -m init -d 365
    kubessl.sh -m renew -c /etc/kubernetes/admin.conf -t cnf/admin.cnf
    kubessl.sh -m renew -c /etc/kubernetes/controller-manager.conf -t cnf/controller-manager.cnf
    kubessl.sh -m renew -c /etc/kubernetes/scheduler.conf -t cnf/scheduler.cnf
    kubessl.sh -m kubelet -d 365
```

**Instructions**

1. Initial Kubernetes Certificate
```sh
mkdir -p /etc/kubernetes/pki
cd /etc/kubernetes
git clone https://github.com/napat1412/kubernetes-tls-setup.git
cd kubernetes-tls-setup
kubessl.sh -m init -d 365
```
2. Initial Kubernetes Cluster with kubeadm
```sh
kubeadm init --config kubeadm-config.yaml --upload-certs
```
3. Renew Kubernetes Certificate in admin.conf, controller-manager.conf, scheduler.conf
```sh
kubessl.sh -m renew -c /etc/kubernetes/admin.conf -t cnf/admin.cnf
kubessl.sh -m renew -c /etc/kubernetes/controller-manager.conf -t cnf/controller-manager.cnf
kubessl.sh -m renew -c /etc/kubernetes/scheduler.conf -t cnf/scheduler.cnf
```
4. Renew Kubelet Certificate in /var/lib/kubelet/pki
```sh
kubessl.sh -m kubelet -d 365
```

