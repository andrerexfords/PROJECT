#!/usr/bin/env bash
# Bootstrap prereq untuk run modul glchat-aws + interaksi k8s.
#
# Install (idempotent — skip kalau sudah ada):
#   - Terraform     (HashiCorp APT repo)
#   - AWS CLI v2    (resmi dari amazon, bukan apt)
#   - kubectl       (Kubernetes APT repo)
#   - helm          (untuk install Rancher)
#   - jq            (helper utk parse output JSON)
#   - make, curl, unzip, gnupg (pendukung)
#
# Target OS: Ubuntu 22.04+ / Debian 12+ (sesuai spec README upstream)
#
# Usage:
#   ./scripts/setup.sh           # install yang missing
#   FORCE=1 ./scripts/setup.sh   # paksa re-install (skip 'already installed' check)
#   DRY_RUN=1 ./scripts/setup.sh # print perintah, tidak install

set -euo pipefail

FORCE="${FORCE:-0}"
DRY_RUN="${DRY_RUN:-0}"

# ---------- helpers ----------

log()  { echo -e "[\033[36m$(date +%H:%M:%S)\033[0m] $*"; }
ok()   { echo -e "[\033[32m  OK\033[0m] $*"; }
warn() { echo -e "[\033[33mWARN\033[0m] $*"; }

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "  [DRY-RUN] $*"
  else
    eval "$@"
  fi
}

need_install() {
  local cmd="$1"
  if [[ "$FORCE" == "1" ]]; then
    return 0
  fi
  command -v "$cmd" >/dev/null 2>&1 && return 1 || return 0
}

SUDO=""
if [[ $EUID -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "ERROR: bukan root + sudo tidak ada. Run sebagai root atau install sudo." >&2
    exit 1
  fi
fi

# ---------- OS check ----------

if [[ ! -f /etc/os-release ]]; then
  warn "/etc/os-release tidak ada, asumsi Ubuntu/Debian-compatible"
else
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) ok "OS: $PRETTY_NAME" ;;
    *) warn "OS tidak teruji ($ID). Script ini disesuaikan untuk Ubuntu/Debian." ;;
  esac
fi

# ---------- base packages ----------

log "Update apt index & install base packages..."
run "$SUDO apt-get update -y"
run "$SUDO apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release unzip make jq software-properties-common"
ok "Base packages ready"

# ---------- Terraform ----------

if need_install terraform; then
  log "Install Terraform (HashiCorp APT repo)..."
  run "curl -fsSL https://apt.releases.hashicorp.com/gpg | $SUDO gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg"
  run "echo \"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \$(lsb_release -cs) main\" | $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null"
  run "$SUDO apt-get update -y"
  run "$SUDO apt-get install -y terraform"
  ok "Terraform installed: $(command -v terraform 2>/dev/null || echo '(dry-run)')"
else
  ok "Terraform sudah ada: $(terraform version | head -1)"
fi

# ---------- AWS CLI v2 ----------

if need_install aws; then
  log "Install AWS CLI v2..."
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64)  AWS_ZIP="awscli-exe-linux-x86_64.zip" ;;
    aarch64) AWS_ZIP="awscli-exe-linux-aarch64.zip" ;;
    *) echo "ERROR: arch tidak didukung: $ARCH" >&2; exit 1 ;;
  esac
  TMP=$(mktemp -d)
  run "curl -fsSL https://awscli.amazonaws.com/$AWS_ZIP -o $TMP/awscli.zip"
  run "unzip -q $TMP/awscli.zip -d $TMP"
  run "$SUDO $TMP/aws/install --update"
  run "rm -rf $TMP"
  ok "AWS CLI installed: $(command -v aws 2>/dev/null || echo '(dry-run)')"
else
  ok "AWS CLI sudah ada: $(aws --version 2>&1)"
fi

# ---------- kubectl ----------

if need_install kubectl; then
  log "Install kubectl (Kubernetes APT repo, stable v1.30)..."
  K8S_REPO_VER="v1.30"
  run "curl -fsSL https://pkgs.k8s.io/core:/stable:/$K8S_REPO_VER/deb/Release.key | $SUDO gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
  run "echo \"deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$K8S_REPO_VER/deb/ /\" | $SUDO tee /etc/apt/sources.list.d/kubernetes.list >/dev/null"
  run "$SUDO apt-get update -y"
  run "$SUDO apt-get install -y kubectl"
  ok "kubectl installed: $(command -v kubectl 2>/dev/null || echo '(dry-run)')"
else
  ok "kubectl sudah ada: $(kubectl version --client 2>/dev/null | head -1 || true)"
fi

# ---------- helm ----------

if need_install helm; then
  log "Install helm (script resmi)..."
  TMP=$(mktemp -d)
  run "curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o $TMP/get-helm-3.sh"
  run "chmod +x $TMP/get-helm-3.sh"
  run "$SUDO $TMP/get-helm-3.sh"
  run "rm -rf $TMP"
  ok "helm installed: $(command -v helm 2>/dev/null || echo '(dry-run)')"
else
  ok "helm sudah ada: $(helm version --short 2>&1)"
fi

# ---------- summary ----------

echo
log "Versi terinstall:"
for tool in terraform aws kubectl helm jq make git; do
  if command -v "$tool" >/dev/null 2>&1; then
    case "$tool" in
      terraform) v=$(terraform version | head -1) ;;
      aws)       v=$(aws --version 2>&1) ;;
      kubectl)   v=$(kubectl version --client 2>/dev/null | grep -i "client version" | head -1) ;;
      helm)      v=$(helm version --short 2>&1) ;;
      *)         v=$($tool --version 2>&1 | head -1) ;;
    esac
    printf "  %-10s %s\n" "$tool" "$v"
  else
    printf "  %-10s %s\n" "$tool" "(NOT INSTALLED)"
  fi
done

echo
log "Setup selesai. Next steps:"
echo "  1) aws configure                # set AWS credentials"
echo "  2) cd modules/glchat-aws && cp terraform.tfvars.example terraform.tfvars"
echo "  3) edit terraform.tfvars (key_name, ami_id, allowed_ssh_cidr)"
echo "  4) cd ../.. && make infra-provision"
