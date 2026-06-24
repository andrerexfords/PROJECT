#!/usr/bin/env bash
# Install RKE2 cluster (server di master + agent di workers).
#
# Dijalankan dari laptop user. SSH ke bastion (public), lalu via -J jumphost
# ke master/worker (private subnet). Hasil: kubeconfig lokal di
# ./kubeconfig-glchat untuk dipakai kubectl.
#
# Scope:
#   - Install RKE2 server di master
#   - Install RKE2 agent di worker-be/fe/db (+ gpu kalau INCLUDE_GPU=1)
#   - Download kubeconfig + rewrite server URL ke master public IP
#   - (Tidak install Rancher — pakai scripts/install-rancher.sh terpisah)
#
# Usage:
#   ./scripts/install-cluster.sh
#   INCLUDE_GPU=1 ./scripts/install-cluster.sh
#   DRY_RUN=1 ./scripts/install-cluster.sh           # cuma print rencana
#   AUTO=1 ./scripts/install-cluster.sh              # skip konfirmasi
#   SSH_KEY=~/.ssh/my-keypair.pem ./scripts/install-cluster.sh
#
# Env vars:
#   REMOTE_USER     (default: ubuntu)
#   RKE2_VERSION    (default: v1.32.5+rke2r1)
#   SSH_KEY         (default: pakai ssh-agent)
#   INCLUDE_GPU     (default: 0)
#   DRY_RUN         (default: 0)
#   AUTO            (default: 0)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$PROJECT_ROOT/modules/glchat-aws"

INCLUDE_GPU="${INCLUDE_GPU:-0}"
DRY_RUN="${DRY_RUN:-0}"
AUTO="${AUTO:-0}"

REMOTE_USER="${REMOTE_USER:-ubuntu}"
RKE2_VERSION="${RKE2_VERSION:-v1.32.5+rke2r1}"
SSH_KEY="${SSH_KEY:-}"

# ---------- helpers ----------

log()  { echo -e "[\033[36m$(date +%H:%M:%S)\033[0m] $*"; }
ok()   { echo -e "[\033[32m  OK\033[0m] $*"; }
warn() { echo -e "[\033[33mWARN\033[0m] $*"; }
err()  { echo -e "[\033[31m ERR\033[0m] $*" >&2; }
die()  { err "$1"; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || die "'$1' tidak ada di PATH. Run: make setup"; }
require terraform; require jq; require ssh; require scp

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
[[ -n "$SSH_KEY" ]] && SSH_OPTS="$SSH_OPTS -i $SSH_KEY"

# Helper: SSH ke bastion langsung
ssh_bastion() { ssh $SSH_OPTS "$REMOTE_USER@$BASTION_IP" "$@"; }

# Helper: SSH ke private node via bastion
ssh_via_bastion() {
  local target="$1"; shift
  ssh $SSH_OPTS -J "$REMOTE_USER@$BASTION_IP" "$REMOTE_USER@$target" "$@"
}

run_remote() {
  # Args: target_ip, command
  local target="$1"; shift
  local cmd="$*"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "  [DRY-RUN] ssh $REMOTE_USER@$target: $cmd"
    return 0
  fi
  if [[ "$target" == "$BASTION_IP" ]]; then
    ssh_bastion "$cmd"
  else
    ssh_via_bastion "$target" "$cmd"
  fi
}

# ---------- 1. Read terraform output ----------

log "Read terraform output dari $TF_DIR..."
cd "$TF_DIR"

TF_OUT=$(terraform output -json 2>/dev/null) || die "Gagal baca terraform output. Pastikan 'make infra-provision' sudah dijalankan."

BASTION_IP=$(echo "$TF_OUT"    | jq -r '.instance_public_ips.value.bastion // empty')
MASTER_PUB_IP=$(echo "$TF_OUT" | jq -r '.instance_public_ips.value.master // empty')
MASTER_PRIV=$(echo "$TF_OUT"   | jq -r '.instance_private_ips.value.master // empty')
WORKER_BE=$(echo "$TF_OUT"     | jq -r '.instance_private_ips.value["worker-be"] // empty')
WORKER_FE=$(echo "$TF_OUT"     | jq -r '.instance_private_ips.value["worker-fe"] // empty')
WORKER_DB=$(echo "$TF_OUT"     | jq -r '.instance_private_ips.value["worker-db"] // empty')
GPU_IP=$(echo "$TF_OUT"        | jq -r '.instance_private_ips.value.gpu // empty')

[[ -z "$BASTION_IP"    ]] && die "Bastion IP kosong di terraform output"
[[ -z "$MASTER_PUB_IP" ]] && die "Master public IP kosong"
[[ -z "$MASTER_PRIV"   ]] && die "Master private IP kosong"
[[ -z "$WORKER_BE"     ]] && die "Worker-BE private IP kosong"
[[ -z "$WORKER_FE"     ]] && die "Worker-FE private IP kosong"
[[ -z "$WORKER_DB"     ]] && die "Worker-DB private IP kosong"

WORKERS=("$WORKER_BE" "$WORKER_FE" "$WORKER_DB")
WORKER_LABELS=("worker-be" "worker-fe" "worker-db")

if [[ "$INCLUDE_GPU" == "1" ]]; then
  [[ -z "$GPU_IP" ]] && die "INCLUDE_GPU=1 tapi GPU IP kosong. Apply ulang dengan include_gpu=true."
  WORKERS+=("$GPU_IP")
  WORKER_LABELS+=("worker-gpu")
fi

ok "Bastion (public)  = $BASTION_IP"
ok "Master  (public)  = $MASTER_PUB_IP"
ok "Master  (private) = $MASTER_PRIV"
for i in "${!WORKERS[@]}"; do
  ok "${WORKER_LABELS[$i]} (private) = ${WORKERS[$i]}"
done

# ---------- 2. Test SSH connectivity ----------

log "Test SSH ke bastion + semua node..."
if [[ "$DRY_RUN" != "1" ]]; then
  ssh_bastion 'echo "bastion ok"' >/dev/null || die "SSH ke bastion gagal. Cek SSH_KEY / ssh-agent."
  ssh_via_bastion "$MASTER_PRIV" 'echo "master ok"' >/dev/null || die "SSH ke master via jumphost gagal."
  for w in "${WORKERS[@]}"; do
    ssh_via_bastion "$w" "echo 'worker $w ok'" >/dev/null || die "SSH ke worker $w gagal."
  done
fi
ok "SSH connectivity OK ke semua node"

# ---------- 3. Konfirmasi ----------

echo
log "Rencana install:"
echo "  1. RKE2 server (master)  : $MASTER_PRIV   (version $RKE2_VERSION)"
echo "  2. RKE2 agent (workers)  : ${WORKERS[*]}"
echo "  3. Download kubeconfig   : $PROJECT_ROOT/kubeconfig-glchat"
echo "     (server URL di-rewrite ke $MASTER_PUB_IP:6443)"
echo

if [[ "$DRY_RUN" == "1" ]]; then
  log "DRY_RUN=1 → stop di sini."
  exit 0
fi

if [[ "$AUTO" != "1" ]]; then
  read -r -p "Lanjut install? [y/N] " yn
  case "$yn" in y|Y|yes|YES) ;; *) log "Dibatalkan."; exit 0 ;; esac
fi

# ---------- 4. Install RKE2 server di master ----------

log "Install RKE2 server di master ($MASTER_PRIV)..."
ssh_via_bastion "$MASTER_PRIV" bash <<REMOTE
set -euo pipefail

if systemctl is-active --quiet rke2-server; then
  echo "RKE2 server sudah jalan, skip install."
else
  # Config: bind ke 0.0.0.0, allow master public IP sebagai tls-san
  sudo mkdir -p /etc/rancher/rke2
  sudo tee /etc/rancher/rke2/config.yaml >/dev/null <<EOF
write-kubeconfig-mode: "0644"
tls-san:
  - $MASTER_PRIV
  - $MASTER_PUB_IP
node-label:
  - node-role=master
EOF

  curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION=$RKE2_VERSION sh -
  sudo systemctl enable --now rke2-server
fi

# Tunggu sampai server ready (cek node-token + kubeconfig terbentuk)
for i in {1..60}; do
  if sudo test -s /var/lib/rancher/rke2/server/node-token && sudo test -s /etc/rancher/rke2/rke2.yaml; then
    echo "RKE2 server ready."
    break
  fi
  echo "Wait RKE2 server... (\$i/60)"
  sleep 5
done

# Symlink kubectl + tambah ke PATH (helper)
sudo ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
REMOTE

ok "RKE2 server installed"

# ---------- 5. Ambil node-token ----------

log "Ambil node-token dari master..."
NODE_TOKEN=$(ssh_via_bastion "$MASTER_PRIV" 'sudo cat /var/lib/rancher/rke2/server/node-token' | tr -d '\r\n')
[[ -z "$NODE_TOKEN" ]] && die "node-token kosong"
ok "Token diperoleh (${#NODE_TOKEN} chars)"

SERVER_URL="https://${MASTER_PRIV}:9345"

# ---------- 6. Install RKE2 agent di workers ----------

log "Install RKE2 agent di ${#WORKERS[@]} worker(s)..."

for i in "${!WORKERS[@]}"; do
  W_IP="${WORKERS[$i]}"
  W_LABEL="${WORKER_LABELS[$i]}"
  log "  → $W_LABEL ($W_IP)..."

  # Label sesuai workload
  case "$W_LABEL" in
    worker-be)  K_LABEL="workload=backend" ;;
    worker-fe)  K_LABEL="workload=frontend" ;;
    worker-db)  K_LABEL="workload=database" ;;
    worker-gpu) K_LABEL="workload=gpu" ;;
    *)          K_LABEL="workload=generic" ;;
  esac

  ssh_via_bastion "$W_IP" bash <<REMOTE
set -euo pipefail

if systemctl is-active --quiet rke2-agent; then
  echo "RKE2 agent sudah jalan di \$(hostname), skip install."
  exit 0
fi

sudo mkdir -p /etc/rancher/rke2
sudo tee /etc/rancher/rke2/config.yaml >/dev/null <<EOF
server: $SERVER_URL
token: $NODE_TOKEN
node-label:
  - $K_LABEL
EOF

curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_TYPE=agent INSTALL_RKE2_VERSION=$RKE2_VERSION sh -
sudo systemctl enable --now rke2-agent

echo "Agent started di \$(hostname)"
REMOTE
  ok "  $W_LABEL joined"
done

# ---------- 7. Download kubeconfig ----------

log "Download kubeconfig ke local..."
TMP_KCFG=$(mktemp)
ssh_via_bastion "$MASTER_PRIV" 'sudo cat /etc/rancher/rke2/rke2.yaml' > "$TMP_KCFG"

# Rewrite server URL: 127.0.0.1 → master public IP
sed -i.bak "s#127.0.0.1#$MASTER_PUB_IP#g" "$TMP_KCFG"
rm "${TMP_KCFG}.bak"

LOCAL_KCFG="$PROJECT_ROOT/kubeconfig-glchat"
mv "$TMP_KCFG" "$LOCAL_KCFG"
chmod 600 "$LOCAL_KCFG"

ok "Kubeconfig saved: $LOCAL_KCFG"

# ---------- 8. Verifikasi cluster ----------

log "Tunggu semua node Ready..."
export KUBECONFIG="$LOCAL_KCFG"

if command -v kubectl >/dev/null 2>&1; then
  for i in {1..30}; do
    READY=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)
    EXPECTED=$((1 + ${#WORKERS[@]}))
    if [[ "$READY" -ge "$EXPECTED" ]]; then
      ok "Semua $READY/$EXPECTED node Ready"
      break
    fi
    echo "  Wait... $READY/$EXPECTED Ready ($i/30)"
    sleep 10
  done

  echo
  log "Cluster state:"
  kubectl get nodes -o wide
else
  warn "kubectl tidak ada di laptop ini. Jalankan: export KUBECONFIG=$LOCAL_KCFG"
fi

echo
ok "INSTALL CLUSTER SELESAI."
echo
echo "Next steps:"
echo "  1) export KUBECONFIG=$LOCAL_KCFG"
echo "  2) kubectl get nodes                  # verifikasi"
echo "  3) make k8s-label-nodes               # apply label/taint (Task 3 — kalau Makefile sudah ada)"
echo "  4) ./scripts/install-rancher.sh       # install Rancher UI (optional)"
