#!/usr/bin/env bash
# Install Rancher UI di cluster RKE2 yang sudah ready.
#
# Asumsi:
#   - install-cluster.sh sudah dijalankan (cluster ready + ./kubeconfig-glchat ada)
#   - kubectl + helm sudah ter-install di laptop
#
# Yang dilakukan:
#   1. Install cert-manager (dependency Rancher untuk TLS)
#   2. Install Rancher via Helm dengan self-signed cert
#   3. Print URL + bootstrap password
#
# Usage:
#   ./scripts/install-rancher.sh
#   RANCHER_HOSTNAME=rancher.client.com ./scripts/install-rancher.sh
#   RANCHER_PASSWORD='S3cretPwd' ./scripts/install-rancher.sh
#
# Env vars:
#   KUBECONFIG          (default: ./kubeconfig-glchat di project root)
#   RANCHER_HOSTNAME    (default: rancher.<master_public_ip>.nip.io)
#   RANCHER_PASSWORD    (default: random 16 chars)
#   RANCHER_VERSION     (default: latest stable, lihat https://github.com/rancher/rancher/releases)
#   CERT_MANAGER_VERSION (default: v1.15.3)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

KUBECONFIG="${KUBECONFIG:-$PROJECT_ROOT/kubeconfig-glchat}"
export KUBECONFIG

CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.15.3}"
RANCHER_VERSION="${RANCHER_VERSION:-}"
RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-}"
RANCHER_PASSWORD="${RANCHER_PASSWORD:-}"

log()  { echo -e "[\033[36m$(date +%H:%M:%S)\033[0m] $*"; }
ok()   { echo -e "[\033[32m  OK\033[0m] $*"; }
err()  { echo -e "[\033[31m ERR\033[0m] $*" >&2; }
die()  { err "$1"; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || die "'$1' tidak ada di PATH"; }

require kubectl
require helm

[[ -f "$KUBECONFIG" ]] || die "Kubeconfig tidak ada di $KUBECONFIG. Run install-cluster.sh dulu."

# ---------- 1. Auto-detect master public IP untuk default hostname ----------

if [[ -z "$RANCHER_HOSTNAME" ]]; then
  TF_DIR="$PROJECT_ROOT/modules/glchat-aws"
  if command -v terraform >/dev/null 2>&1 && [[ -f "$TF_DIR/terraform.tfstate" || -d "$TF_DIR/.terraform" ]]; then
    MASTER_PUB=$(terraform -chdir="$TF_DIR" output -raw 2>/dev/null | grep -A2 'instance_public_ips' | grep master | awk -F'"' '{print $4}' || true)
    if [[ -z "$MASTER_PUB" ]]; then
      MASTER_PUB=$(terraform -chdir="$TF_DIR" output -json 2>/dev/null | jq -r '.instance_public_ips.value.master // empty')
    fi
    [[ -n "$MASTER_PUB" ]] && RANCHER_HOSTNAME="rancher.${MASTER_PUB}.nip.io"
  fi
fi

[[ -z "$RANCHER_HOSTNAME" ]] && RANCHER_HOSTNAME="rancher.local"

# ---------- 2. Generate password kalau tidak di-set ----------

if [[ -z "$RANCHER_PASSWORD" ]]; then
  RANCHER_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#%' </dev/urandom | head -c 20)
  log "Auto-generated password (catat sekarang!)"
fi

# ---------- 3. Verifikasi cluster ----------

log "Verifikasi cluster..."
kubectl cluster-info >/dev/null || die "Gagal akses cluster. Cek KUBECONFIG."
NODES_READY=$(kubectl get nodes --no-headers | awk '$2=="Ready"' | wc -l)
ok "Cluster reachable, $NODES_READY node Ready"

# ---------- 4. Install cert-manager ----------

log "Install cert-manager $CERT_MANAGER_VERSION..."
helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
helm repo update >/dev/null

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version "$CERT_MANAGER_VERSION" \
  --set crds.enabled=true \
  --wait

ok "cert-manager installed"

# ---------- 5. Install Rancher ----------

log "Install Rancher (hostname=$RANCHER_HOSTNAME)..."
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable --force-update >/dev/null
helm repo update >/dev/null

RANCHER_VERSION_FLAG=""
[[ -n "$RANCHER_VERSION" ]] && RANCHER_VERSION_FLAG="--version $RANCHER_VERSION"

helm upgrade --install rancher rancher-stable/rancher \
  --namespace cattle-system --create-namespace \
  $RANCHER_VERSION_FLAG \
  --set hostname="$RANCHER_HOSTNAME" \
  --set bootstrapPassword="$RANCHER_PASSWORD" \
  --set ingress.tls.source=rancher \
  --set replicas=1 \
  --wait --timeout 15m

ok "Rancher installed"

# ---------- 6. Tunggu Rancher pod ready ----------

log "Tunggu Rancher pods ready..."
kubectl -n cattle-system rollout status deploy/rancher --timeout=15m || \
  err "Timeout — cek: kubectl -n cattle-system get pods"

# ---------- 7. Summary ----------

echo
ok "RANCHER INSTALL SELESAI."
echo
echo "Access:"
echo "  URL       : https://$RANCHER_HOSTNAME"
echo "  Username  : admin"
echo "  Password  : $RANCHER_PASSWORD"
echo
echo "Catatan:"
echo "  - Self-signed cert (browser akan warning, klik 'Advanced → Proceed')"
echo "  - .nip.io = wildcard DNS gratis, auto-resolve ke IP di subdomain"
echo "  - Untuk production: ganti ke domain real + cert valid (Let's Encrypt)"
