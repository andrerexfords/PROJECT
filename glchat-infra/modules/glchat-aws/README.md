# Module: `glchat-aws`

Module Terraform **self-contained** untuk provision semua AWS resources yang dibutuhkan cluster GLChat standalone:

- VPC + public subnets + IGW + route table
- Security group (SSH, k8s API, HTTPS/HTTP, intra-cluster)
- EC2 instances (5 wajib + 1 GPU optional) via `terraform-aws-modules/ec2-instance/aws`
- AWS NLB (network load balancer) — menggantikan LB EC2 node

Setelah module ini di-apply, infra sudah ready. Tinggal SSH ke bastion → install RKE2/Rancher pakai repo upstream `gl-sre-helm-charts` (atau via `make install-cluster`).

## Pakai langsung (standalone)

```bash
cd modules/glchat-aws
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: key_name, ami_id, allowed_ssh_cidr

terraform init
terraform plan
terraform apply

# Lihat IP semua instance
terraform output
```

## Pakai dari root project

Dari root `glchat-infra/` ada Makefile wrapper:
```bash
make infra-init
make infra-plan
make infra-provision           # 4 EC2 (no GPU)
make infra-provision-gpu       # 5 EC2 (+ GPU)
make infra-output
make infra-destroy
```

## Input variables

| Variable                | Type            | Default                  | Notes |
|-------------------------|-----------------|--------------------------|-------|
| `aws_region`            | string          | `ap-southeast-1`         | |
| `project_name`          | string          | `glchat`                 | dipakai utk naming |
| `environment`           | string          | `standalone`             | |
| `vpc_cidr`              | string          | `10.0.0.0/16`            | |
| `public_subnet_cidrs`   | list(string)    | 2x /24 di 2 AZ           | |
| `allowed_ssh_cidr`      | string          | `0.0.0.0/0`              | **GANTI ke IP kamu** |
| `key_name`              | string          | —                        | **WAJIB** |
| `ami_id`                | string          | —                        | **WAJIB**, Debian 12 / Ubuntu 22.04 |
| `include_gpu`           | bool            | `false`                  | Task 2: GPU exclude by default |
| `enable_load_balancer`  | bool            | `true`                   | Provision AWS NLB di depan masters & workers |
| `instances`             | map(object)     | bastion + master + worker-be/fe/db | (no LB EC2 — pakai NLB) |
| `gpu_instance`          | object          | g4dn.xlarge              | |

## Outputs

| Output                  | Isi |
|-------------------------|-----|
| `vpc_id`                | ID VPC |
| `vpc_cidr`              | CIDR VPC |
| `public_subnet_ids`     | list ID subnet |
| `security_group_id`     | ID security group |
| `instance_ids`          | map nama → EC2 ID |
| `instance_public_ips`   | map nama → public IP |
| `instance_private_ips`  | map nama → private IP |
| `ssh_commands`          | helper command SSH per instance |
| `nlb_dns_name`          | DNS name AWS NLB — pakai sebagai server_name di config.yml upstream |
| `nlb_zone_id`           | Route53 hosted zone ID (untuk alias record) |
| `nlb_arn`               | ARN NLB |

## Spec instance (default)

**Disk size ikut default AMI** — tidak di-override di module (supaya simpel). Kalau client perlu lebih besar, tambah `root_block_device` di module pemakai.

| Key          | Type          | Role                | Tujuan |
|--------------|---------------|---------------------|--------|
| `bastion`    | `t3.small`    | bastion             | Control center / SSH jumphost |
| `master`     | `t3.xlarge`   | k8s-master          | RKE2 control plane (etcd + controlplane) |
| `worker-be`  | `t3.2xlarge`  | k8s-worker-backend  | Backend workloads |
| `worker-fe`  | `t3.2xlarge`  | k8s-worker-frontend | Frontend workloads |
| `worker-db`  | `t3.2xlarge`  | k8s-worker-database | Database workloads (di-taint) |
| `gpu` (opt)  | `g4dn.xlarge` | k8s-worker-gpu      | AI/ML processing |

Override via `terraform.tfvars` kalau perlu type lain.

**Load balancer = AWS NLB** (bukan EC2). Lihat section "AWS resources" di bawah.

## Network design

Simple — semua EC2 ditaruh di **public subnet** (auto-assign public IP). Alasan:
- Tidak perlu NAT Gateway (saves ~$32/bulan)
- Bastion + LB butuh public IP
- Master/worker bisa diakses via bastion atau langsung (dilindungi SG)

Kalau client butuh private subnet untuk node, fork module ini & adjust.

## AWS resources yg dibuat

| Resource                                  | Jumlah |
|-------------------------------------------|--------|
| VPC                                       | 1      |
| Internet Gateway                          | 1      |
| Public Subnet                             | 2 (di 2 AZ, NLB butuh multi-AZ) |
| Route Table + association                 | 1 + 2  |
| Security Group                            | 1      |
| EC2 Instance                              | 5 (atau 6 dgn GPU) |
| NLB (Network Load Balancer)               | 1 (kalau `enable_load_balancer=true`) |
| NLB Listener                              | 3 (port 6443/443/80) |
| NLB Target Group                          | 3 (api → masters, https/http → workers) |
