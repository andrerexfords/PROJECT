# Configuration Checklist — Value yang Perlu Diisi

Semua nilai yang perlu kamu siapkan sebelum & saat menjalankan automation. Diurutkan sesuai urutan eksekusi.

---

## 📌 Quick checklist (TL;DR)

Sebelum mulai di laptop ber-AWS, siapkan:

- [ ] AWS account + credentials (Access Key + Secret)
- [ ] EC2 key pair sudah dibuat di region target (file `.pem` ada di laptop)
- [ ] AMI ID — Ubuntu 22.04 LTS atau Debian 12 di region target
- [ ] IP publik laptop kamu (untuk SSH whitelist) — cek di https://ifconfig.me
- [ ] Domain name (opsional, kalau pakai custom domain)
- [ ] Secret files untuk apps (GCP service account, kubeconfig, TLS cert) — minta ke `infra@gdplabs.id`
- [ ] Password rancher (random string aman)

---

## 1️⃣ AWS credentials

**Dimana:** environment / `~/.aws/credentials`

```bash
aws configure
# AWS Access Key ID:     <dari IAM user / SSO>
# AWS Secret Access Key: <dari IAM user / SSO>
# Default region:        ap-southeast-1   (atau region pilihan)
# Default output:        json
```

**Atau export:**
```bash
export AWS_ACCESS_KEY_ID=AKIA...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=ap-southeast-1
```

**Permission minimal IAM:** EC2 full, VPC full, ELBv2 full (untuk NLB). Atau pakai `PowerUserAccess` untuk gampangnya.

---

## 2️⃣ Terraform variables (`modules/glchat-aws/terraform.tfvars`)

Copy template + edit:
```bash
cd modules/glchat-aws
cp terraform.tfvars.example terraform.tfvars
```

### Field WAJIB

| Variable           | Contoh value                  | Cara dapat |
|--------------------|-------------------------------|------------|
| `key_name`         | `"my-keypair"`                | Cek di AWS Console → EC2 → Key Pairs (region target). Atau buat baru: `aws ec2 create-key-pair --key-name my-keypair --query 'KeyMaterial' --output text > ~/.ssh/my-keypair.pem && chmod 400 ~/.ssh/my-keypair.pem` |
| `ami_id`           | `"ami-0a0e5d9c7acc336f1"`     | Lihat tabel di bawah |

### Field RECOMMENDED (override)

| Variable               | Default              | Kapan diubah |
|------------------------|----------------------|--------------|
| `aws_region`           | `"ap-southeast-1"`           | Region selain Singapore (Jakarta `ap-southeast-3`, dll) |
| `allowed_ssh_cidr`     | `"0.0.0.0/0"`                | **GANTI** ke IP kamu, mis. `"203.0.113.45/32"`. Cek IP via `curl ifconfig.me` |
| `include_gpu`          | `false`                      | Set `true` kalau client butuh GPU node |
| `project_name`         | `"glchat"`                   | Kalau ingin nama resource beda |
| `environment`          | `"standalone"`               | `dev`, `staging`, `prod`, dll |
| `vpc_cidr`             | `"10.0.0.0/16"`              | Kalau conflict dengan VPC existing |
| `public_subnet_cidrs`  | `["10.0.1.0/24", "10.0.2.0/24"]`   | NLB + bastion (multi-AZ) |
| `private_subnet_cidrs` | `["10.0.11.0/24","10.0.12.0/24"]`  | k8s master + workers (multi-AZ) |
| `single_nat_gateway`   | `true`                       | `true`=1 NAT (~$32/mo), `false`=per-AZ HA (~$64/mo) |
| `enable_load_balancer` | `true`                       | Set `false` kalau LB di-handle terpisah |

### AMI ID Ubuntu 22.04 LTS (per region, per Juni 2026)

> ⚠️ AMI ID berubah setiap update OS. Selalu cek terbaru via AWS CLI sebelum apply.

| Region            | AMI ID (Ubuntu 22.04 amd64) |
|-------------------|------------------------------|
| `ap-southeast-1`  | cari: `aws ec2 describe-images --owners 099720109477 --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text --region ap-southeast-1` |
| `ap-southeast-3`  | (Jakarta) — pakai command yg sama, ganti region |
| `us-east-1`       | (Virginia) — pakai command yg sama |

**Cara cepat (otomatis ambil yang terbaru):**
```bash
aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' \
  --output text \
  --region <REGION>
```

### Contoh `terraform.tfvars` lengkap

```hcl
aws_region   = "ap-southeast-1"
project_name = "glchat"
environment  = "standalone"

key_name = "my-keypair"
ami_id   = "ami-0a0e5d9c7acc336f1"   # ganti dengan output AMI search

allowed_ssh_cidr = "203.0.113.45/32"  # IP kantor kamu

include_gpu          = false
enable_load_balancer = true
```

---

## 3️⃣ Install-cluster orchestrator (env vars saat `make install-cluster`)

Script `scripts/install-cluster.sh` ambil sebagian besar value dari Terraform output (IP & NLB DNS auto-filled), tapi ada beberapa yang perlu di-override via env var.

### Field RECOMMENDED override

| Env var                | Default                          | Kapan diisi |
|------------------------|----------------------------------|-------------|
| `REMOTE_USER`          | `ubuntu`                         | Ganti ke `admin` kalau pakai Debian, atau `ec2-user` kalau Amazon Linux |
| `SSH_KEY`              | (auto-detect dari ssh-agent)     | Path ke file `.pem` kalau key tidak di agent: `~/.ssh/my-keypair.pem` |
| `RANCHER_PASSWORD`     | `CHANGEME-please-edit-config-yml`| **WAJIB ganti** sebelum production. Pakai random string 16+ char |
| `RANCHER_USERNAME`     | `admin`                          | Biasanya `admin` |
| `RANCHER_CLUSTER_NAME` | `glchat-standalone`              | Nama cluster di Rancher UI |
| `LB_DOMAIN`            | (auto = NLB DNS)                 | Kalau pakai custom domain: `"glchat.client.com"` (perlu Route53 record ke NLB DNS) |
| `K8S_VERSION`          | `v1.32.5+rke2r1`                 | Versi RKE2 |
| `UPSTREAM_REPO`        | `https://github.com/GDP-ADMIN/gl-sre-helm-charts` | Ganti kalau pakai fork |

### Cara pakai

**Sekali jalan (interactive prompt):**
```bash
RANCHER_PASSWORD='S3cretP@ssw0rd123!' make install-cluster
```

**Banyak override:**
```bash
REMOTE_USER=admin \
RANCHER_PASSWORD='S3cretP@ssw0rd123!' \
LB_DOMAIN='glchat.client.com' \
RANCHER_CLUSTER_NAME='glchat-prod' \
SSH_KEY=~/.ssh/my-keypair.pem \
make install-cluster
```

**Auto mode (skip konfirmasi):**
```bash
AUTO=1 RANCHER_PASSWORD='...' make install-cluster
```

---

## 4️⃣ `config.generated.yml` (review setelah `install-cluster-dry`)

Setelah `make install-cluster-dry`, cek `config.generated.yml` di root project. Field bertanda **`CHANGEME`** harus diisi sebelum apply beneran:

| Field                                  | Contoh value                  | Catatan |
|----------------------------------------|-------------------------------|---------|
| `infra.rancher.password`               | `"S3cretP@ssw0rd123!"`        | Auto-filled dari `RANCHER_PASSWORD` env. Wajib ganti. |
| `infra.load_balancer.server_name`      | `"glchat.client.com"` atau NLB DNS | Kalau pakai custom domain, point ke NLB DNS via Route53 |

Field lain biasanya **tidak perlu diubah** karena sudah auto-filled dari Terraform output:
- `infra.bastion.ip` ← `instance_public_ips.bastion`
- `infra.rancher.ip` ← `instance_private_ips.master`
- `infra.rke2.nodes[].ip` ← `instance_private_ips.{master,worker-be,worker-fe,worker-db}`
- `infra.load_balancer.internal_ip` / `external_ip` ← `nlb_dns_name`

---

## 5️⃣ Secret files untuk apps (di `apps/config/` repo upstream)

Setelah clone `gl-sre-helm-charts` di bastion (otomatis oleh `install-cluster`), letakkan 3 file ini di `apps/config/`:

| File                          | Sumber                                | Wajib? |
|-------------------------------|---------------------------------------|--------|
| `gcp-service-account.json`    | Minta ke `infra@gdplabs.id`           | ✅ (untuk Docker registry GCP) |
| `kube-config.yaml`            | Di-generate setelah RKE2 install, atau download dari Rancher UI | ✅ (untuk Helm deploy) |
| `tls-secret.yaml`             | Cert SSL untuk domain kamu — bisa Let's Encrypt atau custom | ✅ kalau `ssl: true` |

**Untuk scope task sekarang (infrastructure only),** kalau install app gagal karena 3 file ini belum ada, **TIDAK MASALAH** — yang penting tahap infra (RKE2 + Rancher) sudah jadi. Catat error-nya di `docs/errors.md` aja.

---

## 6️⃣ Domain & DNS (opsional, untuk production)

Kalau pakai custom domain (bukan NLB DNS langsung):

1. **Buat A/CNAME record** di Route53 atau DNS provider:
   ```
   glchat.client.com   CNAME   glchat-standalone-nlb-1234abcd.elb.ap-southeast-1.amazonaws.com
   ```
   (NLB DNS dapat dari `make infra-output` setelah provision)

2. **Generate TLS cert** untuk domain:
   - Let's Encrypt via cert-manager
   - Atau upload manual ke `apps/config/tls-secret.yaml`

3. **Set `LB_DOMAIN`** env saat `make install-cluster`:
   ```bash
   LB_DOMAIN='glchat.client.com' make install-cluster
   ```

---

## 📋 Ringkasan dokumentasi yang sudah ada

| File                            | Isi |
|---------------------------------|-----|
| `README.md` (root)              | Quickstart 5-step + reference command + struktur folder + mapping ke task list |
| `modules/glchat-aws/README.md`  | Module-specific: input vars, outputs, spec instance, AWS resources, network design |
| `docs/configuration.md`         | **(file ini)** — value checklist semua yang perlu diisi |
| `docs/taint-and-label.md`       | Konsep taint/label, 3 effect, strategi BE/FE/DB, opsi apply native vs standalone, contoh pod spec per workload |
| `docs/errors.md`                | Template log error `make infra-standalone-scripts` per entry (date, command, stage, error, root cause, solution, verifikasi) |
| `docs/gpu-exclusion-plan.md`    | PR plan modif Makefile upstream — additive approach, proposed change, verifikasi steps |
| `docs/timeline.md`              | Timeline per task dengan status, date, deliverable + action items berikutnya |

Semua docs sudah komprehensif untuk eksekusi & handoff. Kalau ada step yang masih membingungkan, tinggal bilang.
