#!/bin/bash
### Default Value
k8s_pki='/etc/kubernetes/pki'
k8s_ca="${k8s_pki}/ca.crt"
k8s_key="${k8s_pki}/ca.key"
k8s_sa_key="${k8s_pki}/sa.key"
ssl_day=3650

show_help () {
  echo "
Usage: $0 [-m mode] [-c file] [-t file] [-d int] [-h]

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
    $0 -m init -d 365
    $0 -m renew -c /etc/kubernetes/admin.conf -t cnf/kube-admin.cnf
    $0 -m renew -c /etc/kubernetes/controller-manager.conf -t cnf/kube-controller-manager.cnf
    $0 -m renew -c /etc/kubernetes/scheduler.conf -t cnf/kube-scheduler.cnf
    $0 -m kubelet -d 365

"
  exit 0
}

while getopts m:c:t:d:h flag
do
  case "${flag}" in
      m) mode=${OPTARG};;
      c) k8s_conf=${OPTARG};;
      t) ssl_cnf=${OPTARG};;
      d) ssl_day=${OPTARG};;
      h) show_help;;
      *) show_help;;
  esac
done

main () {  
  case "${mode}" in
    init) mode_init;;
    renew) mode_renew;;
    kubelet) mode_kubelet;;
    *) show_help;;
  esac
}

check_ca () {
  if [ ! -f "$k8s_ca" ]; then
    echo "kubernetes-ca: \"$k8s_ca\" does not exist."
    exit 0
  fi
  if [ ! -f "$k8s_key" ]; then
    echo "kubernetes-ca-key: \"$k8s_key\" does not exist."
    exit 0
  fi
}

clean_up () {
  echo "!!! Clean up !!!"
  rm -rfv tmp.conf
  rm -rfv tmp.key
  rm -rfv tmp.csr
  rm -rfv tmp.crt
}

mode_renew () {
  echo "!!! Renew Certificate in kubernetes configuration file !!!"
  ### Verify required argument
  if [ -z "$k8s_conf" ] || [ -z "$ssl_cnf" ]; then
    echo "please specify -c <k8s-config> and -t <openssl-template>"
    exit 0
  fi

  ### Verify required file
  check_ca
  if [ ! -f "$k8s_conf" ]; then
    echo "kubernetes-config: \"$k8s_conf\" does not exist."
    exit 0
  fi
  if [ ! -f "$ssl_cnf" ]; then
    echo "openssl-template: \"$ssl_cnf\" does not exist."
    exit 0
  fi

  ### Signed Certificate
  awk '$1 ~ /^ *client-key-data/' $k8s_conf | awk '{print $NF}' | base64 -d > tmp.key

  openssl req -new -key tmp.key -out tmp.csr -config  $ssl_cnf
  openssl x509 -req -days $ssl_day -in  tmp.csr -CA $k8s_ca -CAkey $k8s_key \
   -extensions v3_ext -extfile $ssl_cnf \
   -CAcreateserial -out tmp.crt

  ### Re-write File .conf
  OLD_CERT=`awk '$1 ~ /^ *client-certificate-data/' $k8s_conf | awk '{print $NF}'`
  NEW_CERT=`base64 -w 0 tmp.crt`
  cp -f $k8s_conf tmp.conf
  awk 'index($1, "client-certificate-data")!=1' tmp.conf > $k8s_conf
  echo "    #client-certificate-data: $OLD_CERT" >> $k8s_conf
  echo "    client-certificate-data: $NEW_CERT" >> $k8s_conf
  
  clean_up
}

mode_init () {
  echo "!!! Initial kubernetes certificate (ca.key & ca.crt) !!!"
  if [ -f "$k8s_key" ]; then
    echo "Use existing private key: ${k8s_ca}"
    if [ -f "$k8s_ca" ]; then
      echo "Use existing root certificate: ${k8s_ca}"
    else
      echo "Create Root CA: ${k8s_ca}"
    fi
  else
    while true; do
      read -p "Do you want to gernerate new root certificate? [Y/N]: " confirm
      case $confirm in
        [Yy]* ) echo "Generate Root CA: ${k8s_ca}";
                openssl genrsa -out $k8s_key 2048;
                openssl req -x509 -nodes -days $ssl_day -key $k8s_key \
                 -out $k8s_ca -config cnf/ca.cnf -extensions v3_ext;
                break;;
        [Nn]* ) exit;;
        * ) echo "Please type Y or N.";;
      esac
    done
  fi
  
  echo "!!! Initial sa.key & sa.pub !!!"
  if [ -f "$k8s_sa_key" ]; then
    echo "Use existing private key: ${k8s_sa_key}"
    if [ -f "$k8s_sa_key" ]; then
      echo "Use existing public key: ${k8s_pki}/sa.pub"
    else
      echo "Generate public key: ${k8s_pki}/sa.pub"
      openssl rsa -in "$k8s_sa_key" -outform PEM -pubout -out "${k8s_pki}/sa.pub"
    fi
  else
    echo "Generate private & public key: ${k8s_pki}/sa.key, sa.pub"
    openssl genrsa -out "$k8s_sa_key" 2048
    openssl rsa -in "$k8s_sa_key" -outform PEM -pubout -out "${k8s_pki}/sa.pub"
  fi

  echo "!!! Renew or Initial Certificate for apiserver !!!"
  if [ ! -f "${k8s_pki}/apiserver.key" ]; then
    echo "Generate private key: ${k8s_pki}/apiserver.key"
    openssl genrsa -out "${k8s_pki}/apiserver.key" 2048
  fi
  openssl req -new -key "${k8s_pki}/apiserver.key" \
   -out "${k8s_pki}/apiserver.csr" -config cnf/apiserver.cnf
  openssl x509 -req -days $ssl_day -in "${k8s_pki}/apiserver.csr" \
   -CA $k8s_ca -CAkey $k8s_key \
   -CAcreateserial -out "${k8s_pki}/apiserver.crt" \
   -extensions v3_ext -extfile cnf/apiserver.cnf

  echo "!!! Renew or Initial Certificate for apiserver-kubelet-client !!!"
  if [ ! -f "${k8s_pki}/apiserver-kubelet-client.key" ]; then
    echo "Generate private key: ${k8s_pki}/apiserver-kubelet-client.key"
    openssl genrsa -out "${k8s_pki}/apiserver-kubelet-client.key" 2048
  fi
  openssl req -new -key "${k8s_pki}/apiserver-kubelet-client.key" \
   -out "${k8s_pki}/apiserver-kubelet-client.csr" \
   -config cnf/apiserver-kubelet-client.cnf
  openssl x509 -req -days $ssl_day -in "${k8s_pki}/apiserver-kubelet-client.csr" \
   -CA $k8s_ca -CAkey $k8s_key \
   -CAcreateserial -out "${k8s_pki}/apiserver-kubelet-client.crt" \
   -extensions v3_ext -extfile cnf/apiserver-kubelet-client.cnf

  echo "!!! Renew or Initial Certificate for front-proxy-ca !!!"
  if [ ! -f "${k8s_pki}/front-proxy-ca.key" ]; then
    echo "Generate private key: ${k8s_pki}/front-proxy-ca.key"
    openssl genrsa -out "${k8s_pki}/front-proxy-ca.key" 2048
  fi
  openssl req -new -key "${k8s_pki}/front-proxy-ca.key" \
   -out "${k8s_pki}/front-proxy-ca.csr" -config cnf/front-proxy-ca.cnf
  openssl x509 -req -days $ssl_day -in "${k8s_pki}/front-proxy-ca.csr" \
   -CA $k8s_ca -CAkey $k8s_key \
   -CAcreateserial -out "${k8s_pki}/front-proxy-ca.crt" \
   -extensions v3_ext -extfile cnf/front-proxy-ca.cnf

  echo "!!! Renew or Initial Certificate for front-proxy-client !!!"
  if [ ! -f "${k8s_pki}/front-proxy-client.key" ]; then
    echo "Generate private key: ${k8s_pki}/front-proxy-client.key"
    openssl genrsa -out "${k8s_pki}/front-proxy-client.key" 2048
  fi
  openssl req -new -key "${k8s_pki}/front-proxy-client.key" \
   -out "${k8s_pki}/front-proxy-client.csr" -config cnf/front-proxy-client.cnf
  openssl x509 -req -days $ssl_day -in "${k8s_pki}/front-proxy-client.csr" \
   -CA "${k8s_pki}/front-proxy-ca.crt" -CAkey "${k8s_pki}/front-proxy-ca.key" \
   -CAcreateserial -out "${k8s_pki}/front-proxy-client.crt" \
   -extensions v3_ext -extfile cnf/front-proxy-client.cnf

}

mode_kubelet () {
  echo "!!! Renew kubelet certificate !!!"
  check_ca
  date=`date '+%Y-%m-%d-%H-%M-%S'`
  kubelet_pki='/var/lib/kubelet/pki'
  kubelet_pem="${kubelet_pki}/kubelet-client-${date}.pem"
  kubelet_symb="${kubelet_pki}/kubelet-client-current.pem"
  openssl pkey -in $kubelet_symb -out tmp.key

  openssl req -new -key tmp.key -out tmp.csr -config cnf/kubelet.cnf
  openssl x509 -req -days $ssl_day -in tmp.csr -CA $k8s_ca -CAkey $k8s_key \
   -CAcreateserial -out tmp.crt \
   -extensions v3_ext -extfile cnf/kubelet.cnf

  echo "!!! Generate Certificate: ${kubelet_pem} !!!"
  cat tmp.crt >  $kubelet_pem
  cat tmp.key >> $kubelet_pem
  
  echo "!!! Update Symbolic Link: ${kubelet_symb} !!!"
  ln -sf $kubelet_pem $kubelet_symb
  
  clean_up
}

main
echo "!!! Finish !!!"
