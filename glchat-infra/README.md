# GLChat Infra — Quickstart

Helper untuk task automation infrastruktur GLChat. Bagian dari workflow 2 layer:

1. **`glchat-infra/`** (folder ini) — Terraform untuk provision 4-5 EC2 di AWS
2. **`gl-sre-helm-charts/`** (clone sibling) — upstream repo yang install RKE2/Rancher/apps via `make infra-standalone-scripts`

Layout di laptop target:
```
~/projects/
├── glchat-infra/             ← Terraform + helper docs (FOLDER INI)
└── gl-sre-helm-charts/       ← clone https://github.com/GDP-ADMIN/gl-sre-helm-charts
```

---

## Prereq

| Tool      | Versi minimal | Cek |
|-----------|---------------|-----|
| Terraform | 1.5+          | `terraform -version` |
| AWS CLI   | 2.x           | `aws --version` |
| kubectl   | 1.27+         | `kubectl version --client` |
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
make infra-provision     # default: VPC + 4 EC2 (bastion + LB + master + worker, NO GPU)
make infra-output        # catat public/private IP
```

Kalau perlu GPU node:
```bash
make infra-provision-gpu
```

### Step 2 — Clone repo upstream (sibling folder)

```bash
cd ..
git clone https://github.com/GDP-ADMIN/gl-sre-helm-charts
cd gl-sre-helm-charts
```

### Step 3 — Isi `config.yml` repo upstream

Isi dengan IP dari `make infra-output`:
- `infra.bastion.ip`         — bastion public IP
- `infra.rancher.ip`         — master private IP
- `infra.rke2.nodes[]`       — master + worker (private IP)
- `infra.load_balancer.*`    — LB internal IP + domain
- `infra.rke2.nodes[].labels` — pakai `gen-ai=application` / `gen-ai=dpo`

Letakkan file rahasia di `apps/config/`:
- `gcp-service-account.json` (minta ke `infra@gdplabs.id`)
- `kube-config.yaml`
- `tls-secret.yaml`

### Step 4 — Run installer dari bastion

```bash
# SSH ke bastion (forward agent supaya bisa SSH ke node lain)
ssh -A <user>@<bastion-public-ip>

# Di bastion
cd gl-sre-helm-charts
make infra-standalone-scripts ARGS="--exclude gpu-node"   # tanpa GPU (Task 2)
# ATAU
make infra-standalone-scripts                              # dengan GPU
```

**Setiap error yang muncul → tulis ke `docs/errors.md`** pakai template (Task 1c-d).

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
| `make infra-provision`     | Terraform apply (VPC + 4 EC2, no GPU) |
| `make infra-provision-gpu` | Terraform apply (VPC + 5 EC2, + GPU) |
| `make infra-output`        | Print IP/ID semua instance + VPC info |
| `make infra-destroy`       | Destroy SEMUA resource (VPC + EC2, HATI-HATI) |
| `make handoff`             | Print instruksi step 2-4 di terminal |
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
│   └── glchat-aws/                # SATU module: VPC + SG + EC2 (4 atau 5 dgn GPU)
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── versions.tf
│       ├── terraform.tfvars.example
│       └── README.md
├── scripts/
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
