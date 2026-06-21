# GLChat Infra — Quickstart

Helper untuk task automation infrastruktur GLChat. Bagian dari workflow 2 layer:

1. **`glchat-infra/`** (folder ini) — Terraform untuk provision 5-6 EC2 + AWS NLB
2. **`gl-sre-helm-charts/`** (clone sibling) — upstream repo yang install RKE2/Rancher/apps via `make infra-standalone-scripts`

**Arsitektur cluster:** bastion + master + worker-be + worker-fe + worker-db (+ optional GPU). Load balancer pakai **AWS NLB** (bukan EC2).

Layout di laptop target:
```
~/projects/
├── glchat-infra/             ← Terraform + helper docs (FOLDER INI)
└── gl-sre-helm-charts/       ← clone https://github.com/GDP-ADMIN/gl-sre-helm-charts
```

---

## Prereq

Quick install (Ubuntu/Debian):
```bash
make setup           # install terraform, aws cli, kubectl, jq (idempotent)
make setup-dry       # preview tanpa install
```

Atau manual:

| Tool      | Versi minimal | Cek |
|-----------|---------------|-----|
| Terraform | 1.5+          | `terraform -version` |
| AWS CLI   | 2.x           | `aws --version` |
| kubectl   | 1.27+         | `kubectl version --client` |
| jq        | any           | `jq --version` |
| make      | any           | `make --version` |
| git       | any           | `git --version` |

AWS credentials ter-configure:
```bash
aws configure
# atau export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_DEFAULT_REGION
```

---

## End-to-end flow

### Step 1 — Provision AWS infra (Terraform, di folder ini)

Semua AWS resources (VPC + subnets + IGW + SG + EC2) di-bundle dalam **satu module** `modules/glchat-aws/`. Tidak perlu siapkan VPC/subnet existing.

```bash
cd modules/glchat-aws
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: key_name, ami_id, allowed_ssh_cidr
cd ../..

make infra-plan          # cek dulu
make infra-provision     # default: VPC + NLB + 5 EC2 (bastion + master + worker-be/fe/db, NO GPU)
make infra-output        # catat public/private IP + NLB DNS
```

Kalau perlu GPU node:
```bash
make infra-provision-gpu
```

### Step 2 — Install RKE2 + Rancher (otomatis via `install-cluster`)

Script `install-cluster.sh` baca terraform output, generate `config.yml` (IPs auto-filled), copy ke bastion, lalu run installer upstream.

```bash
# Dry-run dulu — cuma generate config, tidak SSH
make install-cluster-dry
# Hasil ada di config.generated.yml — review & edit field CHANGEME

# Jalankan beneran (default NO GPU, sesuai Task 2)
make install-cluster

# Include GPU node
make install-cluster-gpu
```

Override opsional via env var (sebelum `make`):
```bash
REMOTE_USER=admin RANCHER_PASSWORD='S3cret!' LB_DOMAIN='glchat.client.com' make install-cluster
```

Sebelum jalankan, letakkan file rahasia di repo upstream (clone-nya akan di bastion):
- `apps/config/gcp-service-account.json` (minta ke `infra@gdplabs.id`)
- `apps/config/kube-config.yaml`
- `apps/config/tls-secret.yaml`

**Setiap error yang muncul → tulis ke `docs/errors.md`** pakai template (Task 1c-d).

#### Alternatif manual (kalau `install-cluster` tidak cocok)

`make handoff` print instruksi step-by-step untuk:
1. Clone `gl-sre-helm-charts` sebagai sibling folder
2. Isi `config.yml` manual
3. SSH bastion + run installer

### Step 5 — Label & taint nodes

**Cara native (recommended):** isi `labels`/`taints` di `config.yml`, lalu re-apply via repo upstream:
```bash
make infra-standalone-scripts ARGS="--include label-taints"
```

**Cara standalone (alternatif):** pakai script di folder ini, butuh `KUBECONFIG`:
```bash
cd ../glchat-infra
export KUBECONFIG=/path/to/kubeconfig
make k8s-label-nodes-dry    # preview perintah
make k8s-label-nodes        # apply
```

Detail konsep + skema label/taint per workload: lihat `docs/taint-and-label.md`.

---

## Semua perintah

```bash
make help
```

Quick reference:
| Command                    | Fungsi |
|----------------------------|--------|
| `make setup`               | Install prereq tools (terraform/aws/kubectl/jq) di laptop |
| `make infra-provision`     | Terraform apply (VPC + NLB + 5 EC2, no GPU) |
| `make infra-provision-gpu` | Terraform apply (VPC + NLB + 6 EC2, + GPU) |
| `make infra-output`        | Print IP/ID semua instance + VPC info |
| `make install-cluster`     | Auto install RKE2+Rancher via bastion (no GPU) |
| `make install-cluster-gpu` | Sama, include GPU |
| `make install-cluster-dry` | Generate config.generated.yml saja |
| `make infra-destroy`       | Destroy SEMUA resource (VPC + EC2, HATI-HATI) |
| `make handoff`             | Print instruksi manual (alternatif install-cluster) |
| `make k8s-label-nodes`     | Apply label/taint nodes (standalone) |
| `make k8s-label-nodes-dry` | Preview perintah label/taint |

---

## Struktur

```
glchat-infra/
├── Makefile                       # wrapper Terraform + k8s label/taint
├── README.md                      # file ini
├── .gitignore                     # ignore tfstate, tfvars, pem, dll
├── modules/
│   └── glchat-aws/                # SATU module: VPC + SG + NLB + 5/6 EC2
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── versions.tf
│       ├── terraform.tfvars.example
│       └── README.md
├── scripts/
│   ├── setup.sh                   # bootstrap prereq (terraform, aws cli, kubectl, jq)
│   ├── install-cluster.sh         # orchestrate install RKE2+Rancher via bastion
│   └── label-taint-nodes.sh       # standalone: connect cluster + label/taint
└── docs/
    ├── errors.md                  # log error `make infra-standalone-scripts` (Task 1c-d)
    ├── taint-and-label.md         # konsep taint/label + skema GLChat (Task 3)
    └── gpu-exclusion-plan.md      # PR plan modif Makefile upstream (Task 2)
```

---

## Mapping ke task list

| Task                                                       | Due        | Status awal | File/Output |
|------------------------------------------------------------|------------|-------------|-------------|
| 1a — provide 4/5 EC2 via terraform module                  | 22 Jun     | ✅ Scaffold | `modules/glchat-aws/` |
| 1b — running `make infra-standalone-scripts`               | 22 Jun     | ⚠️  Run di bastion | (di repo upstream) |
| 1c-d — list error + solusi di docs                         | 22 Jun     | ⚠️  Isi setelah run | `docs/errors.md` |
| 2 — exclude GPU as default + command Makefile              | 24 Jun     | ✅ Plan ready | `docs/gpu-exclusion-plan.md` |
| 3 — script connect k8s + taint, integrate ke Makefile      | 26 Jun     | ✅ Done | `scripts/label-taint-nodes.sh` + Makefile target |

---

## Troubleshooting

| Masalah | Fix |
|---------|-----|
| Run gagal? | Cek `docs/errors.md`, mungkin sudah ada solusi sejenis |
| Mau cleanup? | `make infra-destroy` (HATI-HATI: hapus semua EC2) |
| State Terraform stuck? | `make clean` (hapus `.terraform/`, **bukan** state) |
| Tidak bisa SSH ke node lain dari bastion? | Pakai `ssh -A`, atau setup `~/.ssh/config` |
