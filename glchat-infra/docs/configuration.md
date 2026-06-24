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
- [ ] (Optional) Password Rancher custom — kalau tidak set, auto-generated

---

## 0️⃣ Terraform state di S3

State Terraform disimpan di `s3://prj-idvend/prj-aws-glchat/standalone/terraform.tfstate` (region `us-east-1`).

**Untuk laptop yang sudah pernah apply** (state masih local): lihat [`docs/migrate-state-to-s3.md`](migrate-state-to-s3.md) untuk cara migrate.

**Untuk laptop baru** (clone fresh): tinggal `terraform init`, state auto-pull dari S3.

**Prerequisite:** bucket `prj-idvend` harus exist + AWS creds punya permission S3 (lihat migration doc).

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
| `public_subnet_cidrs`  | `["10.0.1.0/24", "10.0.2.0/24"]`   | Bastion + master (multi-AZ) |
| `private_subnet_cidrs` | `["10.0.11.0/24","10.0.12.0/24"]`  | Workers + gpu (multi-AZ) |
| `single_nat_gateway`   | `true`                       | `true`=1 NAT (~$32/mo), `false`=per-AZ HA (~$64/mo) |

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

## 3️⃣ Install-cluster (env vars saat `make install-cluster`)

Script `scripts/install-cluster.sh` install RKE2 from scratch via SSH. Tidak butuh repo upstream.

### Field RECOMMENDED override

| Env var          | Default                       | Kapan diisi |
|------------------|-------------------------------|-------------|
| `REMOTE_USER`    | `ubuntu`                      | `admin` (Debian), `ec2-user` (Amazon Linux) |
| `SSH_KEY`        | (auto-detect dari ssh-agent)  | Path `.pem` kalau key tidak di agent: `~/.ssh/my-keypair.pem` |
| `RKE2_VERSION`   | `v1.32.5+rke2r1`              | Versi RKE2 |
| `INCLUDE_GPU`    | `0`                           | Set `1` untuk include GPU worker (atau pakai `make install-cluster-gpu`) |
| `AUTO`           | `0`                           | Set `1` untuk skip konfirmasi interaktif |

**Sekali jalan:**
```bash
make install-cluster
```

**Banyak override:**
```bash
REMOTE_USER=admin SSH_KEY=~/.ssh/my-keypair.pem AUTO=1 make install-cluster
```

Output: `kubeconfig-glchat` di root project. Pakai:
```bash
export KUBECONFIG=$(pwd)/kubeconfig-glchat
kubectl get nodes
```

---

## 4️⃣ Install-rancher (optional, env vars)

Script `scripts/install-rancher.sh` install Rancher UI di cluster.

| Env var               | Default                              | Catatan |
|-----------------------|--------------------------------------|---------|
| `KUBECONFIG`          | `./kubeconfig-glchat`                | Path kubeconfig dari install-cluster |
| `RANCHER_HOSTNAME`    | `rancher.<master_pub_ip>.nip.io`     | Auto-detect dari master IP. Override ke custom domain kalau ada Route53 record |
| `RANCHER_PASSWORD`    | (auto-generate random 20 chars)      | Override pakai value sendiri |
| `RANCHER_VERSION`     | (latest stable)                      | Pin ke versi tertentu kalau perlu |
| `CERT_MANAGER_VERSION`| `v1.15.3`                            | Dependency Rancher |

**Sekali jalan:**
```bash
make install-rancher
```

**Custom hostname:**
```bash
RANCHER_HOSTNAME=rancher.client.com RANCHER_PASSWORD='S3cret!' make install-rancher
```

URL + password akan di-print di akhir. Self-signed cert (browser warning OK).

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
