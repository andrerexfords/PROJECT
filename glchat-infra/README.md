# GLChat Infra — Quickstart

Helper end-to-end untuk automation infra GLChat (Task 1 + 2 + 3):

1. **Provision AWS** — VPC + EC2 via Terraform (`modules/glchat-aws/`)
2. **Install cluster** — RKE2 server + agent via SSH dari scratch (`scripts/install-cluster.sh`)
3. **Install Rancher** — UI management via Helm (`scripts/install-rancher.sh`, optional)
4. **Label/taint nodes** — assign workload per role (`scripts/label-taint-nodes.sh`)

**Arsitektur cluster:** bastion + master + worker-be + worker-fe + worker-db (+ optional GPU). **Tanpa LB terpisah** — master public IP jadi endpoint k8s API & Rancher. **Network:** bastion + master di public subnet, workers di private subnet (egress via NAT Gateway).

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

Semua AWS resources (VPC + subnets + IGW + SG + NLB + EC2) di-bundle dalam **satu module** `modules/glchat-aws/`. Tidak perlu siapkan VPC/subnet existing.

> 📋 **Sebelum mulai:** baca [`docs/configuration.md`](docs/configuration.md) untuk daftar lengkap value yang perlu disiapkan (AWS creds, key pair, AMI ID, dll).

```bash
cd modules/glchat-aws
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: key_name, ami_id, allowed_ssh_cidr
cd ../..

make infra-plan          # cek dulu
make infra-provision     # default: VPC + 5 EC2 (bastion + master + worker-be/fe/db, NO GPU)
make infra-output        # catat public/private IP
```

Kalau perlu GPU node:
```bash
make infra-provision-gpu
```

### Step 2 — Install RKE2 cluster (otomatis via `install-cluster`)

Script `install-cluster.sh` baca terraform output, SSH ke master & workers via bastion, install RKE2 (server di master, agent di workers), download kubeconfig ke laptop.

```bash
# Dry-run dulu — cuma cek SSH connectivity + print rencana
make install-cluster-dry

# Jalankan beneran (default NO GPU, sesuai Task 2)
make install-cluster

# Include GPU worker
make install-cluster-gpu
```

Override opsional via env var:
```bash
REMOTE_USER=admin SSH_KEY=~/.ssh/my-keypair.pem make install-cluster
```

Output: `kubeconfig-glchat` di root project. Pakai untuk kubectl:
```bash
export KUBECONFIG=$(pwd)/kubeconfig-glchat
kubectl get nodes
```

### Step 3 — Install Rancher UI (optional)

Setelah cluster ready, install Rancher untuk management UI:
```bash
make install-rancher
```

Auto-generate password kalau tidak di-set. Pakai `.nip.io` untuk wildcard DNS default. Override:
```bash
RANCHER_HOSTNAME=rancher.client.com RANCHER_PASSWORD='S3cret!' make install-rancher
```

**Setiap error yang muncul → tulis ke `docs/errors.md`** pakai template (Task 1c-d).

### Step 4 — Label & taint nodes (Task 3)

Setelah cluster ready, apply label/taint per workload (BE/FE/DB):
```bash
export KUBECONFIG=$(pwd)/kubeconfig-glchat
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
| `make setup`               | Install prereq tools (terraform/aws/kubectl/helm/jq) |
| `make infra-provision`     | Terraform apply (VPC + 5 EC2, no GPU) |
| `make infra-provision-gpu` | Terraform apply (VPC + 6 EC2, + GPU) |
| `make infra-output`        | Print IP semua instance |
| `make install-cluster`     | SSH ke nodes, install RKE2 server+agents |
| `make install-cluster-gpu` | Sama, include GPU worker |
| `make install-cluster-dry` | Cek SSH connectivity + print rencana |
| `make install-rancher`     | Install Rancher UI via Helm (optional) |
| `make infra-destroy`       | Destroy SEMUA resource (HATI-HATI) |
| `make k8s-label-nodes`     | Apply label/taint nodes (Task 3) |
| `make k8s-label-nodes-dry` | Preview perintah label/taint |

---

## Struktur

```
glchat-infra/
├── Makefile                       # wrapper Terraform + k8s label/taint
├── README.md                      # file ini
├── .gitignore                     # ignore tfstate, tfvars, pem, dll
├── modules/
│   └── glchat-aws/                # SATU module: VPC + SG + 5/6 EC2 (tanpa LB)
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── versions.tf
│       ├── terraform.tfvars.example
│       └── README.md
├── scripts/
│   ├── setup.sh                   # bootstrap prereq (terraform/aws/kubectl/helm/jq)
│   ├── install-cluster.sh         # install RKE2 server di master + agents di workers
│   ├── install-rancher.sh         # install Rancher UI via Helm (optional)
│   └── label-taint-nodes.sh       # label/taint k8s nodes per workload
└── docs/
    ├── configuration.md           # ⭐ checklist SEMUA value yang perlu diisi (baca dulu!)
    ├── errors.md                  # log error `make infra-standalone-scripts` (Task 1c-d)
    ├── taint-and-label.md         # konsep taint/label + skema GLChat (Task 3)
    ├── gpu-exclusion-plan.md      # PR plan modif Makefile upstream (Task 2)
    └── timeline.md                # progress timeline per task
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
