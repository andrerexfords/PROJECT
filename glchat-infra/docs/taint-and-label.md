# Taint & Label Nodes — Konsep + Implementasi GLChat

Referensi untuk Task 3. Konsep singkat + skema label/taint per node sesuai arsitektur baru (master + worker BE/FE/DB + optional GPU).

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
  - key: "workload"
    operator: "Equal"
    value: "database"
    effect: "NoSchedule"
```

Cara mikir cepat: **label = "siapa saya?"**, **taint = "siapa boleh masuk?"**.

---

## Strategi label/taint GLChat (current)

Default yang dipasang `scripts/label-taint-nodes.sh`:

| Node                              | Labels                                                                     | Taints                            | Alasan |
|-----------------------------------|----------------------------------------------------------------------------|-----------------------------------|--------|
| `glchat-standalone-master`        | `node-role.kubernetes.io/control-plane=true`, `node-role=master`           | (default RKE2)                    | Control plane |
| `glchat-standalone-worker-be`     | `node-role.kubernetes.io/worker=true`, `workload=backend`                  | —                                 | Pod backend di sini |
| `glchat-standalone-worker-fe`     | `node-role.kubernetes.io/worker=true`, `workload=frontend`                 | —                                 | Pod frontend di sini |
| `glchat-standalone-worker-db`     | `node-role.kubernetes.io/worker=true`, `workload=database`                 | `workload=database:NoSchedule`    | Database isolated, hanya pod ber-toleration yang boleh masuk |
| `glchat-standalone-gpu` (opt)     | `node-role.kubernetes.io/worker=true`, `accelerator=nvidia`, `workload=gpu`| `nvidia.com/gpu=true:NoSchedule`  | GPU mahal, hanya pod GPU |

**Bastion di-skip** — bukan k8s node.

---

## Cara apply

### Opsi A — Native via repo upstream (lewat `install-cluster`)

Sudah otomatis: `make install-cluster` generate `config.yml` dengan field `labels`/`taints` per node, lalu repo upstream apply lewat komponennya. Jadi setelah `make install-cluster` selesai, label/taint sudah terpasang.

Re-apply manual (kalau perlu update tanpa rerun semua):
```bash
# Di bastion
cd gl-sre-helm-charts
make infra-standalone-scripts ARGS="--include label-taints"
```

### Opsi B — Standalone script (alternatif)

Pakai script di folder ini. Cocok untuk:
- Cluster yang BUKAN di-install via `gl-sre-helm-charts`
- Re-label/taint cepat tanpa harus rerun installer
- Testing / learning

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

## Contoh: deploy pod sesuai workload

### Backend pod
```yaml
spec:
  nodeSelector:
    workload: backend
```

### Frontend pod
```yaml
spec:
  nodeSelector:
    workload: frontend
```

### Database pod (butuh toleration karena di-taint)
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

Hasil: pod backend hanya landed di `worker-be`, frontend di `worker-fe`, database di `worker-db`. Pod tanpa toleration **tidak akan nyasar** ke `worker-db`.

---

## Cara connect script ke k8s cluster

Script `label-taint-nodes.sh` mengandalkan `KUBECONFIG`. Opsi:

| Cara | Command |
|------|---------|
| Export env var | `export KUBECONFIG=~/.kube/glchat-standalone.yaml` |
| Default path | `mkdir -p ~/.kube && cp kubeconfig ~/.kube/config` |
| Dari Rancher UI | Cluster → Kubeconfig File → download |
| Dari RKE2 master | SSH master → `sudo cat /etc/rancher/rke2/rke2.yaml` |

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
