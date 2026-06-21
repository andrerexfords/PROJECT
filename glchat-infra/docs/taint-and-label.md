# Taint & Label Nodes — Konsep + Implementasi GLChat

Referensi untuk Task 3. Berisi: konsep singkat, dua cara apply di GLChat (native upstream vs script standalone), contoh skema label per workload.

---

## Konsep singkat

**Label** = key-value attached ke node, fungsinya untuk *selection*. Pod pilih node lewat `nodeSelector` / `nodeAffinity`.

**Taint** = "tolakan" yang dipasang di node. Pod **tidak** akan dijadwalkan ke node ber-taint, **kecuali** pod punya `toleration` yang cocok.

Format taint: `key=value:effect`

| Effect              | Behavior |
|---------------------|----------|
| `NoSchedule`        | Pod baru tidak landed; pod existing tetap jalan |
| `PreferNoSchedule`  | Best-effort hindari; bisa landed kalau tidak ada node lain |
| `NoExecute`         | Pod baru tidak landed; pod existing tanpa toleration di-evict |

Contoh toleration di pod spec:
```yaml
tolerations:
  - key: "nvidia.com/gpu"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
```

**Cara mikir cepat:** label = "siapa saya?", taint = "siapa boleh masuk?".

---

## Dua cara apply di GLChat

### Opsi A — Native via repo upstream (RECOMMENDED untuk standalone install)

Repo `gl-sre-helm-charts` sudah punya komponen `label-taints` di scripts-nya.
Kamu cuma perlu isi `config.yml`:

```yaml
infra:
  rke2:
    nodes:
      - name: master-1
        ip: 10.128.0.6
        role: [etcd, controlplane]
        labels:
          - gen-ai=application
        taints:
          - gen-ai=application:NoSchedule

      - name: worker-1
        ip: 10.128.0.10
        role: worker
        labels:
          - gen-ai=dpo

      # Contoh app/database separation (sesuai task: App=node a, DB=node b)
      - name: worker-app
        ip: 10.128.0.11
        role: worker
        labels:
          - workload=app

      - name: worker-db
        ip: 10.128.0.12
        role: worker
        labels:
          - workload=database
        taints:
          - workload=database:NoSchedule
```

Jalankan (di bastion):
```bash
make infra-standalone-scripts                          # full install (label-taints included)
make infra-standalone-scripts ARGS="--include label-taints"   # HANYA re-apply label/taint
```

### Opsi B — Standalone script (kalau cluster sudah ada / di-manage manual)

Pakai `scripts/label-taint-nodes.sh` di folder ini. Cocok untuk:
- Cluster yang BUKAN di-install via `gl-sre-helm-charts`
- Re-label/taint cepat tanpa harus rerun installer
- Testing/learning

Naming convention: script mencocokkan node berdasarkan pola `<PROJECT_NAME>-<ENVIRONMENT>-<role>` (default: `glchat-standalone-*`, sesuai Terraform).

```bash
export KUBECONFIG=/path/to/kubeconfig

# Dry-run dulu (print perintah, tidak apply):
make k8s-label-nodes-dry

# Apply beneran:
make k8s-label-nodes

# Override naming kalau project/env beda:
make k8s-label-nodes PROJECT_NAME=foo ENVIRONMENT=prod
```

---

## Strategi label/taint default

Default yang dipasang script (bisa diubah di `scripts/label-taint-nodes.sh`):

| Node                          | Labels                                                                 | Taints                            | Alasan |
|-------------------------------|------------------------------------------------------------------------|-----------------------------------|--------|
| `glchat-standalone-master`    | `node-role.kubernetes.io/control-plane=true`, `gen-ai=application`     | `gen-ai=application:NoSchedule`   | Control plane, pisahkan dari workload umum |
| `glchat-standalone-worker`    | `node-role.kubernetes.io/worker=true`, `gen-ai=dpo`                    | —                                 | Worker default — terima workload GLChat |
| `glchat-standalone-gpu`       | `node-role.kubernetes.io/worker=true`, `accelerator=nvidia`, `gen-ai=gpu` | `nvidia.com/gpu=true:NoSchedule` | GPU mahal, hanya untuk pod GPU |

**Bastion & loadbalancer di-skip** — mereka biasanya bukan k8s node.

---

## Contoh App/Database separation

Skenario task: "App == node a, Database == node b" — supaya app & database tidak berebut resource di node yang sama.

**Setup label/taint:**
```bash
kubectl label node node-a workload=app --overwrite
kubectl label node node-b workload=database --overwrite
kubectl taint node node-b workload=database:NoSchedule --overwrite
```

**Pod App** (pakai `nodeSelector`, **tidak perlu toleration** karena node-a tanpa taint):
```yaml
spec:
  nodeSelector:
    workload: app
```

**Pod Database** (pakai `nodeSelector` + `toleration` karena node-b di-taint):
```yaml
spec:
  nodeSelector:
    workload: database
  tolerations:
    - key: "workload"
      operator: "Equal"
      value: "database"
      effect: "NoSchedule"
```

Hasil: pod App **hanya** landed di node-a, pod Database **hanya** landed di node-b, dan **tidak ada pod lain** yang nyasar ke node-b (terlindungi taint).

---

## Cara connect script ke k8s cluster

Script `label-taint-nodes.sh` mengandalkan `KUBECONFIG`. Opsi:

| Cara | Command |
|------|---------|
| Export env var | `export KUBECONFIG=~/.kube/glchat-standalone.yaml` |
| Default path | `mkdir -p ~/.kube && cp kubeconfig ~/.kube/config` |
| Dari Rancher UI | Cluster → Kubeconfig File → download |
| Dari RKE2/kubeadm master | SSH master → `cat /etc/rancher/rke2/rke2.yaml` (RKE2) atau `/etc/kubernetes/admin.conf` (kubeadm) |

Verifikasi connection sebelum run script:
```bash
kubectl cluster-info
kubectl get nodes
```

---

## Verifikasi & rollback

**Cek hasil:**
```bash
kubectl get nodes --show-labels
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
kubectl describe node <node-name> | grep -E "Labels|Taints"
```

**Cabut taint** (perhatikan tanda minus di akhir):
```bash
kubectl taint node <node-name> <key>=<value>:<effect>-
```

**Cabut label:**
```bash
kubectl label node <node-name> <key>-
```
