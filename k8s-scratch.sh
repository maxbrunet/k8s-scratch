#!/usr/bin/env bash
set -euo pipefail

K8S_VERSION='v1.12.4'
NODE_SUBNET="192.168.183"
NODE_ID="$(hostname -s | perl -ne 'print $1 if /(\d+)$/')"
NODE_IP="${NODE_SUBNET}.$(( 100 + NODE_ID ))"

if [[ -d /vagrant ]]; then
  LOCAL_TMP='/vagrant/tmp'
  mkdir -p "${LOCAL_TMP}"
else
  LOCAL_TMP='/tmp'
fi

# https://kubernetes.io/docs/setup/scratch/#designing-and-preparing

## https://kubernetes.io/docs/setup/scratch/#learning
## https://kubernetes.io/docs/setup/scratch/#cloud-provider
# https://kubernetes.io/docs/setup/scratch/#nodes
## https://kubernetes.io/docs/setup/scratch/#network

### https://kubernetes.io/docs/setup/scratch/#network-connectivity
SERVICE_CLUSTER_IP_RANGE='10.0.0.0/16'
MASTER_IP="${NODE_SUBNET}.101"

echo '>>> Enabling IPv4 forwarding...'
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/80-ipv4-forward.conf
sysctl --system >/dev/null

### https://kubernetes.io/docs/setup/scratch/#network-policy

## https://kubernetes.io/docs/setup/scratch/#cluster-naming
CLUSTER_NAME='k8s-scratch.local'

## https://kubernetes.io/docs/setup/scratch/#software-binaries
### https://kubernetes.io/docs/setup/scratch/#downloading-and-extracting-kubernetes-binaries

if [[ ! -d "${LOCAL_TMP}/kubernetes" ]]; then
  echo '>>> Downloading Kubernetes server binaries...'
  curl -fsSL "https://dl.k8s.io/${K8S_VERSION}/kubernetes-server-linux-amd64.tar.gz" \
    | tar xzf - -C "${LOCAL_TMP}"
fi

for bin in kubectl kube-proxy kubelet; do
  if [[ ! -x "/usr/local/bin/${bin}" ]]; then
    printf '>>> Installing %s...\n' "${bin}"
    cp "${LOCAL_TMP}/kubernetes/server/bin/${bin}" /usr/local/bin
  fi
done

### https://kubernetes.io/docs/setup/scratch/#selecting-images
ETCD_VERSION='v3.2.24'
TAG="${K8S_VERSION}"
HYPERKUBE_IMAGE="k8s.gcr.io/hyperkube:${TAG}"
ETCD_IMAGE="k8s.gcr.io/etcd:${ETCD_VERSION}"

## https://kubernetes.io/docs/setup/scratch/#security-models
### https://kubernetes.io/docs/setup/scratch/#preparing-certs

K8S_DIR="/srv/kubernetes"
CA_CERT="${K8S_DIR}/ca.crt"
CA_KEY="${LOCAL_TMP}/ca.key"
MASTER_CERT="${K8S_DIR}/server.crt"
MASTER_KEY="${K8S_DIR}/server.key"
MASTER_CSR="${K8S_DIR}/server.csr"
MASTER_CONF="${K8S_DIR}/server.conf"
CLI_CERT="${K8S_DIR}/admin.crt"
CLI_KEY="${K8S_DIR}/admin.key"
CLI_CSR="${K8S_DIR}/admin.csr"

#### https://kubernetes.io/docs/concepts/cluster-administration/certificates/#openssl
mkdir -p "${LOCAL_TMP}${K8S_DIR}" "${K8S_DIR}"

if [[ ! -f "${CA_KEY}" ]]; then
    echo '>>> Generating Certificate Authority...'
    openssl genrsa -out "${CA_KEY}" 4096
    openssl req -x509 -new -nodes -key "${CA_KEY}" -subj "/CN=kubernetes-ca" \
      -sha256 -days 1825 -out "${LOCAL_TMP}/${CA_CERT}"
fi
echo ">>> Installing Certificate Authority..."
cp "${LOCAL_TMP}${CA_CERT}" "${CA_CERT}"


if [[ "${NODE_ID}" -eq 1 ]]; then
  echo '>>> Generating Master certificate...'
  cat > "${MASTER_CONF}" <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[ dn ]
CN = ${MASTER_IP}

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.${CLUSTER_NAME}
DNS.5 = kubernetes.default.svc.${CLUSTER_NAME}
IP.1 = ${MASTER_IP}
IP.2 = 127.0.0.1
#IP.2 = <MASTER_CLUSTER_IP>

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@alt_names
EOF
  openssl genrsa -out "${MASTER_KEY}" 4096
  openssl req -new -key "${MASTER_KEY}" -out "${MASTER_CSR}" \
    -config "${MASTER_CONF}"
  openssl x509 -req -in "${MASTER_CSR}" -CA "${CA_CERT}" -CAkey "${CA_KEY}" \
    -CAcreateserial -out "${MASTER_CERT}" -days 365 \
    -extensions v3_ext -extfile "${MASTER_CONF}"
fi

echo '>>> Generating Client certificate...'
openssl genrsa -out "${CLI_KEY}" 4096
openssl req -new -sha256 -key "${CLI_KEY}" \
  -subj "/O=system:masters/CN=:admin" -out "${CLI_CSR}"
openssl x509 -req -in "${CLI_CSR}" -CA "${CA_CERT}" -CAkey "${CA_KEY}" \
  -CAcreateserial -out "${CLI_CERT}" -days 365 -sha256

### https://kubernetes.io/docs/setup/scratch/#preparing-credentials
TOKENS_FILE="/var/lib/kube-apiserver/known_tokens.csv"
CONTEXT_NAME="k8s-scratch"
KUBE_PROXY_CONFIG="/var/lib/kube-proxy/kubeconfig"
KUBELET_CONFIG="/var/lib/kubelet/kubeconfig"

mkdir -p "${LOCAL_TMP}${TOKENS_FILE%/*}" "${TOKENS_FILE%/*}"

if [ ! -f "${LOCAL_TMP}${TOKENS_FILE}" ]; then
  echo '>>> Generating Admin token...'
  TOKEN="$(
    dd if=/dev/urandom bs=128 count=1 2>/dev/null | base64 \
      | tr -d '=+/[:space:]' | dd bs=32 count=1 2>/dev/null
  )"
  echo "${TOKEN},admin,1" > "${LOCAL_TMP}${TOKENS_FILE}"
else
  echo '>>> Retrieving Admin token...'
  TOKEN="$(perl -ne 'print $1 if /(.*?),/' "${LOCAL_TMP}${TOKENS_FILE}")"
fi

if [[ "${NODE_ID}" -eq 1 ]]; then
    echo '>>> Installing Admin token...'
    cp "${LOCAL_TMP}${TOKENS_FILE}" "${TOKENS_FILE}"
fi

for config in "${HOME}/.kube/config" "${KUBE_PROXY_CONFIG}" "${KUBELET_CONFIG}"; do
  printf '>>> Generating %s...\n' "${config}"
  KUBECONFIG="${config}" kubectl config set-cluster "${CLUSTER_NAME}" \
    --certificate-authority="${CA_CERT}" \
    --embed-certs=true --server="https://127.0.0.1:6443"
  KUBECONFIG="${config}" kubectl config set-credentials "${CONTEXT_NAME}" \
    --client-certificate="${CLI_CERT}" --client-key="${CLI_KEY}" \
    --embed-certs=true --token="${TOKEN}"
  KUBECONFIG="${config}" kubectl config set-context "${CONTEXT_NAME}" \
    --cluster="${CLUSTER_NAME}" --user="${CONTEXT_NAME}"
  KUBECONFIG="${config}" kubectl config use-context "${CONTEXT_NAME}"
done

# https://kubernetes.io/docs/setup/scratch/#configuring-and-installing-base-software-on-nodes
CLUSTER_SUBNET='10.0.0.0/12'
NODE_POD_CIDR="10.${NODE_ID}.0.0"
NODE_BRIDGE_ADDR="10.${NODE_ID}.0.1"
PRIVATE_INTERFACE="$(ip route get "${NODE_SUBNET}" | awk 'NR==1{ print $4 }')"
## https://kubernetes.io/docs/setup/scratch/#docker

### https://docs.docker.com/install/linux/docker-ce/ubuntu/ ###

echo ">>> Installing Docker repository..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository \
  "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) \
  stable"
echo ">>> Installing Docker..."
apt-get update
apt-get install -y docker-ce

### WARNING: No swap limit support
### https://docs.docker.com/install/linux/linux-postinstall/#your-kernel-does-not-support-cgroup-swap-limit-capabilities
echo ">>> Enabling swap limit capabilities (effective at next reboot)..."
sed -i -E 's/^(GRUB_CMDLINE_LINUX=).*/\1"cgroup_enable=memory swapaccount=1"/' /etc/default/grub
update-grub

### https://wiki.debian.org/BridgeNetworkConnections
echo ">>> Installing bridge-utils..."
apt-get install -y bridge-utils
echo ">>> Configuring cbr0 bridge interface..."
cat > /etc/network/interfaces.d/80-crb0.cfg <<EOF
iface cbr0 inet static
      address ${NODE_BRIDGE_ADDR}
      broadcast ${NODE_POD_CIDR}
      netmask 255.255.0.0
      bridge_ports ${PRIVATE_INTERFACE}
      bridge_stp off
      bridge_waitport 0
      bridge_fd 0
      up route add -net ${CLUSTER_SUBNET} dev ${PRIVATE_INTERFACE}
      down route del -net ${CLUSTER_SUBNET} dev ${PRIVATE_INTERFACE}
EOF
echo ">>> Reloading cbr0 configuration..."
ifdown cbr0 && ifup cbr0

echo ">>> Flushing rules from NAT table..."
iptables -t nat -F
if ip link show docker0 >/dev/null 2>&1; then
  echo ">>> Deleting default docker0 bridge..."
  ip link set docker0 down
  ip link delete docker0
fi

echo ">>> Reconfiguring Docker for Kubernetes..."
sed -i -E 's/^#?(DOCKER_OPTS=).*/\1"--bridge=cbr0 --iptables=false --ip-masq=false"/' /etc/default/docker
grep -q 'DOCKER_NOFILE=1000000' /etc/default/docker || echo 'DOCKER_NOFILE=1000000' >> /etc/default/docker
echo ">>> Restarting Docker..."
systemctl restart docker

## https://kubernetes.io/docs/setup/scratch/#rkt ## skip
## https://kubernetes.io/docs/setup/scratch/#kubelet

echo ">>> Configuring systemd service for kubelet..."
# TODO: Update k8s.io scratch documentation
#   - Disambiguate "Otherwise" bullet-point
# TODO: Look into using Kubelet config file
#   Flag --pod-manifest-path has been deprecated,
#   This parameter should be set via the config file
#   specified by the Kubelet's --config flag.
#   See https://kubernetes.io/docs/tasks/administer-cluster/kubelet-config-file/
#   for more information.
cat > /etc/systemd/system/kubelet.service <<EOF
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=http://kubernetes.io/docs/

[Service]
ExecStart=/usr/local/bin/kubelet --kubeconfig="${KUBELET_CONFIG}" --pod-manifest-path=/etc/kubernetes/manifests
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

## https://kubernetes.io/docs/setup/scratch/#kube-proxy

echo ">>> Installing kube-proxy dependencies..."
apt-get install -y conntrack

echo ">>> Configuring systemd service for kube-proxy..."
cat > /etc/systemd/system/kube-proxy.service <<EOF
[Unit]
Description=kube-proxy: The Kubernetes network proxy
Documentation=http://kubernetes.io/docs/

[Service]
ExecStart=/usr/local/bin/kube-proxy --kubeconfig="${KUBE_PROXY_CONFIG}"
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

## https://kubernetes.io/docs/setup/scratch/#networking

echo ">>> Enabling NAT translation for Pods IPs (non-cluster-subnet IPs)..."
iptables -t nat -A POSTROUTING ! -d "${CLUSTER_SUBNET}" \
  -m addrtype ! --dst-type LOCAL -j MASQUERADE
echo ">>> Configuring netfilter rules persistence..."
apt-get install -y netfilter-persistent
sudo netfilter-persistent save

## https://kubernetes.io/docs/setup/scratch/#other

# https://kubernetes.io/docs/setup/scratch/#bootstrapping-the-cluster

if [[ "${NODE_ID}" -eq 1 ]]; then

  mkdir -p /etc/kubernetes/manifests

  ## https://kubernetes.io/docs/setup/scratch/#etcd

  echo ">>> Creating etcd pod manifest..."
  cat > /etc/kubernetes/manifests/etcd.manifest <<EOF
{
  "apiVersion": "v1",
  "kind": "Pod",
  "metadata": {
    "name": "etcd-server-scratch",
    "namespace": "kube-system",
    "annotations": {
      "scheduler.alpha.kubernetes.io/critical-pod": "",
      "seccomp.security.alpha.kubernetes.io/pod": "docker/default"
    }
  },
  "spec": {
    "hostNetwork": true,
    "containers": [
      {
        "name": "etcd-container",
        "image": "${ETCD_IMAGE}",
        "resources": {},
        "command": [
          "etcd",
          "--name etcd-scratch",
          "--listen-peer-urls=http://127.0.0.1:2380",
          "--initial-advertise-peer-urls=http://127.0.0.1:2380",
          "--advertise-client-urls=http://127.0.0.1:2379",
          "--listen-client-urls=http://127.0.0.1:2379",
          "--data-dir=/var/etcd/data-scratch",
          "--initial-cluster=etcd-scratch=http://127.0.0.1:2380"
        ],
        "livenessProbe": {
          "httpGet": {
            "host": "127.0.0.1",
            "port": 2379,
            "path": "/health"
          },
          "initialDelaySeconds": 15,
          "timeoutSeconds": 15
        },
        "ports": [
          {
            "name": "serverport",
            "containerPort": 2380,
            "hostPort": 2380
          },
          {
            "name": "clientport",
            "containerPort": 2379,
            "hostPort": 2379
          }
        ],
        "volumeMounts": [
          {
            "name": "varetcd",
            "mountPath": "/var/etcd",
            "readOnly": false
          },
          {
            "name": "varlogetcd",
            "mountPath": "/var/log/etcd-scratch.log",
            "readOnly": false
          },
          {
            "name": "etc",
            "mountPath": "/srv/kubernetes",
            "readOnly": false
          }
        ]
      }
    ],
    "volumes": [
      {
        "name": "varetcd",
        "hostPath": {
          "path": "/var/etcd"
        }
      },
      {
        "name": "varlogetcd",
        "hostPath": {
          "path": "/var/log/etcd-scratch.log",
          "type": "FileOrCreate"
        }
      },
      {
        "name": "etc",
        "hostPath": {
          "path": "/srv/kubernetes"
        }
      }
    ]
  }
}
EOF

  ## https://kubernetes.io/docs/setup/scratch/#apiserver-controller-manager-and-scheduler

  echo ">>> Creating apiserver pod manifest..."
  cat > /etc/kubernetes/manifests/apiserver.manifest <<EOF
{
  "kind": "Pod",
  "apiVersion": "v1",
  "metadata": {
    "name": "kube-apiserver"
  },
  "spec": {
    "hostNetwork": true,
    "containers": [
      {
        "name": "kube-apiserver",
        "image": "${HYPERKUBE_IMAGE}",
        "command": [
          "/hyperkube",
          "apiserver",
          "--bind-address=127.0.0.1",
          "--address=127.0.0.1",
          "--service-cluster-ip-range=${SERVICE_CLUSTER_IP_RANGE}",
          "--etcd-servers=http://127.0.0.1:2379",
          "--tls-cert-file=/srv/kubernetes/server.cert",
          "--tls-private-key-file=/srv/kubernetes/server.key",
          "--enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,Priority,ResourceQuota",
          "--client-ca-file=/srv/kubernetes/ca.crt",
          "--token-auth-file=/srv/kubernetes/known_tokens.csv",
          "--basic-auth-file=/srv/kubernetes/basic_auth.csv"
        ],
        "ports": [
          {
            "name": "https",
            "hostPort": 443,
            "containerPort": 443
          },
          {
            "name": "local",
            "hostPort": 8080,
            "containerPort": 8080
          }
        ],
        "volumeMounts": [
          {
            "name": "srvkube",
            "mountPath": "/srv/kubernetes",
            "readOnly": true
          },
          {
            "name": "etcssl",
            "mountPath": "/etc/ssl",
            "readOnly": true
          }
        ],
        "livenessProbe": {
          "httpGet": {
            "scheme": "HTTP",
            "host": "127.0.0.1",
            "port": 8080,
            "path": "/healthz"
          },
          "initialDelaySeconds": 15,
          "timeoutSeconds": 15
        }
      }
    ],
    "volumes": [
      {
        "name": "srvkube",
        "hostPath": {
          "path": "/srv/kubernetes"
        }
      },
      {
        "name": "etcssl",
        "hostPath": {
          "path": "/etc/ssl"
        }
      }
    ]
  }
}
EOF

  echo ">>> Creating scheduler pod manifest..."
  cat > /etc/kubernetes/manifests/scheduler.manifest <<EOF
{
  "kind": "Pod",
  "apiVersion": "v1",
  "metadata": {
    "name": "kube-scheduler"
  },
  "spec": {
    "hostNetwork": true,
    "containers": [
      {
        "name": "kube-scheduler",
        "image": "${HYPERKUBE_IMAGE}",
        "command": [
          "/hyperkube",
          "scheduler",
          "--master=127.0.0.1:8080"
        ],
        "livenessProbe": {
          "httpGet": {
            "scheme": "HTTP",
            "host": "127.0.0.1",
            "port": 10251,
            "path": "/healthz"
          },
          "initialDelaySeconds": 15,
          "timeoutSeconds": 15
        }
      }
    ]
  }
}
EOF

  echo ">>> Creating controller-manager pod manifest..."
  cat > /etc/kubernetes/manifests/controller-manager.manifest <<EOF
{
  "kind": "Pod",
  "apiVersion": "v1",
  "metadata": {
    "name": "kube-controller-manager"
  },
  "spec": {
    "hostNetwork": true,
    "containers": [
      {
        "name": "kube-controller-manager",
        "image": "${HYPERKUBE_IMAGE}",
        "command": [
          "/hyperkube",
          "controller-manager",
          "--cluster-cidr=${CLUSTER_SUBNET}",
		  "--service-account-private-key-file=/srv/kubernetes/server.key",
          "--master=127.0.0.1:8080"
        ],
        "volumeMounts": [
          {
            "name": "srvkube",
            "mountPath": "/srv/kubernetes",
            "readOnly": true
          },
          {
            "name": "etcssl",
            "mountPath": "/etc/ssl",
            "readOnly": true
          }
        ],
        "livenessProbe": {
          "httpGet": {
            "scheme": "HTTP",
            "host": "127.0.0.1",
            "port": 10252,
            "path": "/healthz"
          },
          "initialDelaySeconds": 15,
          "timeoutSeconds": 15
        }
      }
    ],
    "volumes": [
      {
        "name": "srvkube",
        "hostPath": {
          "path": "/srv/kubernetes"
        }
      },
      {
        "name": "etcssl",
        "hostPath": {
          "path": "/etc/ssl"
        }
      }
    ]
  }
}
EOF

fi

## https://kubernetes.io/docs/setup/scratch/#starting-cluster-services

echo ">>> Reloading systemd configuration..."
systemctl daemon-reload
echo ">>> Enabling kubelet and kube-proxy services..."
systemctl enable kubelet
systemctl enable kube-proxy
echo ">>> Starting kubelet and kube-proxy services..."
systemctl start kubelet
systemctl start kube-proxy

exit 0
