#!/usr/bin/env bash
# Orchestrate install RKE2 + Rancher di cluster yang sudah di-provision Terraform.
#
# Apa yang dilakukan script ini:
#   1. Baca output `terraform output -json` (butuh modul glchat-aws sudah ter-apply)
#   2. Generate `config.generated.yml` — config.yml dengan IP & LB DNS auto-filled
#   3. SCP config + clone gl-sre-helm-charts di bastion
#   4. Run `make infra-standalone-scripts` di bastion (default --exclude gpu-node, sesuai Task 2)
#
# Arsitektur: bastion + master + worker-be + worker-fe + worker-db (+ optional GPU).
# Load balancer pakai AWS NLB (dns_name dari terraform output).
#
# Usage:
#   ./scripts/install-cluster.sh                 # default no-GPU
#   INCLUDE_GPU=1 ./scripts/install-cluster.sh   # include GPU
#   DRY_RUN=1 ./scripts/install-cluster.sh       # generate config + print perintah, tidak SSH
#   AUTO=1 ./scripts/install-cluster.sh          # skip konfirmasi interaktif

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$PROJECT_ROOT/modules/glchat-aws"

INCLUDE_GPU="${INCLUDE_GPU:-0}"
DRY_RUN="${DRY_RUN:-0}"
AUTO="${AUTO:-0}"

# Override via env
REMOTE_USER="${REMOTE_USER:-ubuntu}"
SSH_KEY="${SSH_KEY:-}"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/GDP-ADMIN/gl-sre-helm-charts}"
RANCHER_USERNAME="${RANCHER_USERNAME:-admin}"
RANCHER_PASSWORD="${RANCHER_PASSWORD:-CHANGEME-please-edit-config-yml}"
RANCHER_CLUSTER_NAME="${RANCHER_CLUSTER_NAME:-glchat-standalone}"
LB_DOMAIN="${LB_DOMAIN:-}"
K8S_VERSION="${K8S_VERSION:-v1.32.5+rke2r1}"

# ---------- helpers ----------

log()  { echo -e "[\033[36m$(date +%H:%M:%S)\033[0m] $*"; }
ok()   { echo -e "[\033[32m  OK\033[0m] $*"; }
err()  { echo -e "[\033[31m ERR\033[0m] $*" >&2; }
die()  { err "$1"; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || die "'$1' tidak ada di PATH. Run: make setup"; }

require terraform
require jq
require ssh
require scp

# ---------- 1. read terraform output ----------

log "Read terraform output dari $TF_DIR..."
cd "$TF_DIR"

TF_OUT=$(terraform output -json 2>/dev/null) || die "Gagal baca terraform output. Pastikan 'make infra-provision' sudah dijalankan."

BASTION_IP=$(echo "$TF_OUT"   | jq -r '.instance_public_ips.value.bastion // empty')
MASTER_IP=$(echo "$TF_OUT"    | jq -r '.instance_private_ips.value.master // empty')
WORKER_BE_IP=$(echo "$TF_OUT" | jq -r '.instance_private_ips.value["worker-be"] // empty')
WORKER_FE_IP=$(echo "$TF_OUT" | jq -r '.instance_private_ips.value["worker-fe"] // empty')
WORKER_DB_IP=$(echo "$TF_OUT" | jq -r '.instance_private_ips.value["worker-db"] // empty')
GPU_IP=$(echo "$TF_OUT"       | jq -r '.instance_private_ips.value.gpu // empty')
NLB_DNS=$(echo "$TF_OUT"      | jq -r '.nlb_dns_name.value // empty')

[[ -z "$BASTION_IP"   ]] && die "Bastion IP kosong di terraform output"
[[ -z "$MASTER_IP"    ]] && die "Master private IP kosong"
[[ -z "$WORKER_BE_IP" ]] && die "Worker-BE private IP kosong"
[[ -z "$WORKER_FE_IP" ]] && die "Worker-FE private IP kosong"
[[ -z "$WORKER_DB_IP" ]] && die "Worker-DB private IP kosong"
[[ -z "$NLB_DNS"      ]] && die "NLB DNS kosong (enable_load_balancer=false?)"

# Default LB_DOMAIN ke NLB DNS kalau user tidak set
[[ -z "$LB_DOMAIN" ]] && LB_DOMAIN="$NLB_DNS"

ok "Bastion (public)     = $BASTION_IP"
ok "Master  (private)    = $MASTER_IP"
ok "Worker-BE (private)  = $WORKER_BE_IP"
ok "Worker-FE (private)  = $WORKER_FE_IP"
ok "Worker-DB (private)  = $WORKER_DB_IP"
[[ -n "$GPU_IP" ]] && ok "GPU (private)        = $GPU_IP"
ok "NLB DNS              = $NLB_DNS"
ok "LB server_name       = $LB_DOMAIN"

# ---------- 2. generate config.generated.yml ----------

CONFIG_OUT="$PROJECT_ROOT/config.generated.yml"
log "Generate $CONFIG_OUT (IP & NLB auto-filled)..."

GPU_NODE_BLOCK=""
if [[ "$INCLUDE_GPU" == "1" && -n "$GPU_IP" ]]; then
  GPU_NODE_BLOCK="
      - name: worker-gpu
        ip: $GPU_IP
        role: worker
        labels:
          - accelerator=nvidia
          - workload=gpu
        taints:
          - nvidia.com/gpu=true:NoSchedule"
fi

cat > "$CONFIG_OUT" <<YAML
# AUTO-GENERATED oleh scripts/install-cluster.sh pada $(date -Iseconds)
# Edit field bertanda CHANGEME sebelum apply ke bastion.
#
# Arsitektur:
#   bastion     - control center (bukan k8s node)
#   master      - RKE2 control plane (etcd + controlplane)
#   worker-be   - backend workloads
#   worker-fe   - frontend workloads
#   worker-db   - database workloads (di-taint)
# Load balancer: AWS NLB ($NLB_DNS)

infra:
  bastion:
    ip: $BASTION_IP
    remote_user: "$REMOTE_USER"

  rancher:
    ip: $MASTER_IP
    username: "$RANCHER_USERNAME"
    password: "$RANCHER_PASSWORD"   # CHANGEME
    cluster_name: "$RANCHER_CLUSTER_NAME"

  rke2:
    kubernetes_version: "$K8S_VERSION"
    nodes:
      - name: master-1
        ip: $MASTER_IP
        role: [etcd, controlplane]
        labels:
          - node-role=master

      - name: worker-be
        ip: $WORKER_BE_IP
        role: worker
        labels:
          - workload=backend

      - name: worker-fe
        ip: $WORKER_FE_IP
        role: worker
        labels:
          - workload=frontend

      - name: worker-db
        ip: $WORKER_DB_IP
        role: worker
        labels:
          - workload=database
        taints:
          - workload=database:NoSchedule
$GPU_NODE_BLOCK

  load_balancer:
    ssl: true
    server_name: "$LB_DOMAIN"           # CHANGEME (kalau pakai custom domain, point ke NLB DNS)
    # AWS NLB pakai DNS name, bukan static IP. Field di bawah diisi DNS untuk kompatibilitas.
    internal_ip: $NLB_DNS
    external_ip: $NLB_DNS

# 'apps:' section TIDAK di-generate — copy dari example upstream lalu sesuaikan.
# Scope task: infrastructure only (kalau perlu app cuma learning app).
YAML

ok "Config generated: $CONFIG_OUT"

# ---------- 3. confirm + show next ----------

ARGS_FLAGS=""
if [[ "$INCLUDE_GPU" != "1" ]]; then
  ARGS_FLAGS="--exclude gpu-node"
  log "Mode: NO GPU (sesuai Task 2 — default exclude)"
else
  log "Mode: WITH GPU (INCLUDE_GPU=1)"
fi

SSH_OPTS=""
[[ -n "$SSH_KEY" ]] && SSH_OPTS="-i $SSH_KEY"
SSH_OPTS="$SSH_OPTS -o StrictHostKeyChecking=accept-new -A"

echo
log "Next steps yang akan dijalankan:"
echo "  1. scp $CONFIG_OUT  $REMOTE_USER@$BASTION_IP:/tmp/config.yml"
echo "  2. ssh $REMOTE_USER@$BASTION_IP:"
echo "     - git clone $UPSTREAM_REPO || (cd gl-sre-helm-charts && git pull)"
echo "     - cp /tmp/config.yml gl-sre-helm-charts/config.yml"
echo "     - cd gl-sre-helm-charts && make infra-standalone-scripts ARGS=\"$ARGS_FLAGS\""
echo

if [[ "$DRY_RUN" == "1" ]]; then
  log "DRY_RUN=1 → stop di sini. Cek $CONFIG_OUT lalu jalankan tanpa DRY_RUN."
  exit 0
fi

if [[ "$AUTO" != "1" ]]; then
  read -r -p "Lanjut SSH ke bastion & install? [y/N] " yn
  case "$yn" in
    y|Y|yes|YES) ;;
    *) log "Dibatalkan. Config tetap ada di $CONFIG_OUT"; exit 0 ;;
  esac
fi

# ---------- 4. execute on bastion ----------

log "Copy config.yml ke bastion..."
scp $SSH_OPTS "$CONFIG_OUT" "$REMOTE_USER@$BASTION_IP:/tmp/config.yml"

log "Clone repo + run installer di bastion..."
ssh $SSH_OPTS "$REMOTE_USER@$BASTION_IP" bash <<REMOTE
set -euo pipefail

if [[ ! -d gl-sre-helm-charts ]]; then
  git clone $UPSTREAM_REPO
fi

cd gl-sre-helm-charts
git pull --ff-only || true
cp /tmp/config.yml ./config.yml

echo "==> WARN: kalau apps/config/{gcp-service-account.json,kube-config.yaml,tls-secret.yaml} belum ada, installer kemungkinan gagal di tahap app."
echo "==> Lanjut tahap infra:"
make infra-standalone-scripts ARGS="$ARGS_FLAGS"
REMOTE

ok "Install selesai. Catat error apapun ke docs/errors.md (Task 1 c-d)."
