# Migrate Terraform State ke S3

Step-by-step migrasi state Terraform dari local file ke S3 bucket `s3://prj-idvend/prj-aws-glchat/standalone/terraform.tfstate`.

## Konteks

| Sebelum | Sesudah |
|---------|---------|
| `modules/glchat-aws/terraform.tfstate` (local) | `s3://prj-idvend/prj-aws-glchat/standalone/terraform.tfstate` (remote) |
| Risiko hilang kalau laptop rusak | Aman, versioned, encrypted |
| Tidak bisa di-share | Tim bisa apply dari laptop berbeda |

Backend config sudah di-add ke `modules/glchat-aws/versions.tf`. Tinggal migrate.

## Prerequisite

1. **Bucket S3 harus EXIST.** Cek dulu:
   ```bash
   aws s3 ls s3://prj-idvend/
   ```

   Kalau belum ada, bikin (sekali saja):
   ```bash
   aws s3api create-bucket \
     --bucket prj-idvend \
     --region us-east-1

   # Enable versioning (penting untuk recover state corruption)
   aws s3api put-bucket-versioning \
     --bucket prj-idvend \
     --versioning-configuration Status=Enabled

   # Enable default encryption
   aws s3api put-bucket-encryption \
     --bucket prj-idvend \
     --server-side-encryption-configuration '{
       "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
     }'

   # Block public access
   aws s3api put-public-access-block \
     --bucket prj-idvend \
     --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
   ```

2. **AWS credentials punya permission:**
   - `s3:ListBucket` di bucket `prj-idvend`
   - `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` di `prj-idvend/prj-aws-glchat/*`

   Test:
   ```bash
   aws s3 cp /tmp/test.txt s3://prj-idvend/prj-aws-glchat/test.txt
   aws s3 rm s3://prj-idvend/prj-aws-glchat/test.txt
   ```

## Migrasi (dari laptop yang punya state local)

⚠️ **Lakukan di laptop yang punya `terraform.tfstate` local existing** (yang habis `make infra-provision`).

### Step 1 — Backup state local

```bash
cd modules/glchat-aws
cp terraform.tfstate ../../terraform.tfstate.LOCAL_BACKUP_$(date +%Y%m%d)
```

### Step 2 — Pull latest code dari git

```bash
cd /path/to/PROJECT
git pull origin main
```

Sekarang `versions.tf` sudah punya backend S3 block.

### Step 3 — Run `terraform init -migrate-state`

```bash
cd glchat-infra/modules/glchat-aws
terraform init -migrate-state
```

Terraform akan deteksi backend baru, lalu tanya:
```
Do you want to copy existing state to the new backend?
  Pre-existing state was found while migrating the previous "local" backend to the
  newly configured "s3" backend. No existing state was found in the newly
  configured "s3" backend. Do you want to copy this state to the new "s3"
  backend? Enter "yes" to copy and "no" to start with an empty state.

  Enter a value:
```

**Jawab: `yes`**

### Step 4 — Verifikasi

```bash
# Cek state di S3
aws s3 ls s3://prj-idvend/prj-aws-glchat/standalone/

# Cek state isi sama
terraform state list           # harus muncul semua resource existing
```

Output `terraform state list` harus include:
```
module.vpc.module.vpc.aws_vpc.this[0]
module.ec2["bastion"]...
module.ec2["master"]...
module.ec2["worker-be"]...
...
aws_security_group.glchat
```

### Step 5 — Hapus state local (optional, setelah konfirmasi S3 OK)

```bash
# State local sudah di-copy ke S3, file local jadi tidak relevan
rm terraform.tfstate terraform.tfstate.backup
```

⚠️ Pastikan dulu `terraform state list` jalan di S3 sebelum hapus local.

### Step 6 — Test plan

```bash
terraform plan
```

Harus tampil `No changes` (karena state-nya sama, infra-nya sama).

## Pakai dari laptop lain

Setelah state di S3, laptop lain tinggal:
```bash
git clone git@github.com:andrerexfords/PROJECT.git
cd PROJECT/glchat-infra/modules/glchat-aws
terraform init     # auto-pull state dari S3
terraform plan     # cek state sama dengan infra
```

Tidak perlu transfer `terraform.tfstate` manual.

## Troubleshooting

### `Error: NoSuchBucket`
Bucket belum dibuat. Lihat **Prerequisite** step 1.

### `Error: AccessDenied`
AWS credentials tidak punya permission ke S3. Cek IAM policy:
```json
{
  "Effect": "Allow",
  "Action": [
    "s3:ListBucket",
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject"
  ],
  "Resource": [
    "arn:aws:s3:::prj-idvend",
    "arn:aws:s3:::prj-idvend/prj-aws-glchat/*"
  ]
}
```

### `Error: Backend configuration changed`
Sudah pernah init dengan backend berbeda. Force re-init:
```bash
terraform init -reconfigure
```

### State terlanjur kosong di S3, infra real masih ada
Restore dari backup:
```bash
cp ../../terraform.tfstate.LOCAL_BACKUP_<date> terraform.tfstate
terraform init -migrate-state
```

## Rollback ke local

Kalau mau balik ke local state:

1. Hapus block `backend "s3" { ... }` di `versions.tf`
2. Run:
   ```bash
   terraform init -migrate-state
   # Jawab "yes" untuk copy back dari S3 ke local
   ```
