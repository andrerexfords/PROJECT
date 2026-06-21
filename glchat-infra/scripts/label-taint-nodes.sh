#!/usr/bin/env bash
# Label & taint k8s nodes setelah cluster siap (Task 3).
#
# Connect ke cluster via $KUBECONFIG, lalu apply label/taint berdasarkan
# pola nama node (sesuai naming Terraform: <project>-<env>-<role>).
#
# Naming convention default (variables.tf):
#   glchat-standalone-master    -> control plane
#   glchat-standalone-worker-be -> backend workloads        (label workload=backend)
#   glchat-standalone-worker-fe -> frontend workloads       (label workload=frontend)
#   glchat-standalone-worker-db -> database workloads       (label workload=database + taint)
#   glchat-standalone-gpu       -> GPU worker               (label + taint nvidia.com/gpu)
#
# Bastion BUKAN k8s node, jadi tidak diproses di sini.
#
# Usage:
#   ./label-taint-nodes.sh                          # apply pakai default KUBECONFIG
#   KUBECONFIG=/path/to/kubeconfig ./label-taint-nodes.sh
#   DRY_RUN=true ./label-taint-nodes.sh             # cek perintah dulu, tanpa apply
#   PROJECT_NAME=foo ENVIRONMENT=prod ./label-taint-nodes.sh  # override naming

set -euo pipefail

PROJECT_NAME="${PROJECT_NAME:-glchat}"
ENVIRONMENT="${ENVIRONMENT:-standalone}"
DRY_RUN="${DRY_RUN:-false}"

KUBECTL="kubectl"
[[ "$DRY_RUN" == "true" ]] && KUBECTL="echo [DRY-RUN] kubectl"

log() { echo "[$(date +%H:%M:%S)] $*"; }
require() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' tidak ditemukan di PATH"; exit 1; }; }

require kubectl

log "Connect ke cluster..."
kubectl cluster-info >/dev/null || { echo "ERROR: gagal connect ke cluster. Cek KUBECONFIG."; exit 1; }

log "List nodes:"
kubectl get nodes -o wide

apply_for_node() {
  local node="$1"
  local prefix="${PROJECT_NAME}-${ENVIRONMENT}-"

  case "$node" in
    *${prefix}master*)
      log "[$node] control-plane -> label node-role=master"
      $KUBECTL label node "$node" node-role.kubernetes.io/control-plane=true --overwrite
      $KUBECTL label node "$node" node-role=master --overwrite
      ;;
    *${prefix}worker-be*)
      log "[$node] backend worker -> label workload=backend"
      $KUBECTL label node "$node" node-role.kubernetes.io/worker=true --overwrite
      $KUBECTL label node "$node" workload=backend --overwrite
      ;;
    *${prefix}worker-fe*)
      log "[$node] frontend worker -> label workload=frontend"
      $KUBECTL label node "$node" node-role.kubernetes.io/worker=true --overwrite
      $KUBECTL label node "$node" workload=frontend --overwrite
      ;;
    *${prefix}worker-db*)
      log "[$node] database worker -> label workload=database + taint NoSchedule"
      $KUBECTL label node "$node" node-role.kubernetes.io/worker=true --overwrite
      $KUBECTL label node "$node" workload=database --overwrite
      $KUBECTL taint node "$node" workload=database:NoSchedule --overwrite
      ;;
    *${prefix}gpu*)
      log "[$node] GPU worker -> label accelerator + taint nvidia.com/gpu"
      $KUBECTL label node "$node" node-role.kubernetes.io/worker=true --overwrite
      $KUBECTL label node "$node" accelerator=nvidia --overwrite
      $KUBECTL label node "$node" workload=gpu --overwrite
      $KUBECTL taint node "$node" nvidia.com/gpu=true:NoSchedule --overwrite
      ;;
    *)
      log "[$node] tidak match pola — skip (cek naming convention kalau ini error)"
      ;;
  esac
}

log "Apply label & taint per node..."
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  apply_for_node "$node"
done

log "Selesai. Verifikasi:"
kubectl get nodes --show-labels
echo
log "Taints:"
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
