# Module: `glchat-aws`

Module Terraform **self-contained** untuk provision semua AWS resources yang dibutuhkan cluster GLChat standalone:

- VPC dengan **public + private subnets** (multi-AZ) + IGW + NAT Gateway + route tables
- Security group (SSH, k8s API, HTTPS/HTTP, intra-cluster)
- EC2 instances (5 wajib + 1 GPU optional) via `terraform-aws-modules/ec2-instance/aws`
  - **Bastion + Master** → public subnet (punya public IP). Master jadi endpoint k8s API & Rancher.
  - **Workers (BE/FE/DB + GPU)** → private subnet (no public IP, akses via bastion/master)

**Tanpa AWS NLB.** Endpoint cluster langsung ke master public IP. Lebih hemat (no NLB cost), tapi tidak HA untuk control plane.

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
| `public_subnet_cidrs`   | list(string)    | 2x /24 (`10.0.1.0/24`, `10.0.2.0/24`) | Untuk NLB + bastion |
| `private_subnet_cidrs`  | list(string)    | 2x /24 (`10.0.11.0/24`, `10.0.12.0/24`) | Untuk k8s master + workers |
| `single_nat_gateway`    | bool            | `true`                   | `true` = 1 NAT (cheap, ~$32/mo), `false` = per-AZ (HA, ~$64/mo) |
| `allowed_ssh_cidr`      | string          | `0.0.0.0/0`              | **GANTI ke IP kamu** — SSH ke bastion/master |
| `key_name`              | string          | —                        | **WAJIB** |
| `ami_id`                | string          | —                        | **WAJIB**, Debian 12 / Ubuntu 22.04 |
| `include_gpu`           | bool            | `false`                  | Task 2: GPU exclude by default |
| `instances`             | map(object)     | bastion + master + worker-be/fe/db | Tanpa LB EC2, tanpa AWS NLB |
| `gpu_instance`          | object          | g4dn.xlarge              | |

## Outputs

| Output                  | Isi |
|-------------------------|-----|
| `vpc_id`                | ID VPC |
| `vpc_cidr`              | CIDR VPC |
| `public_subnet_ids`     | list ID public subnet (bastion + master) |
| `private_subnet_ids`    | list ID private subnet (workers + gpu) |
| `nat_gateway_ips`       | EIP NAT Gateway — outbound IP private nodes ke internet |
| `security_group_id`     | ID security group |
| `instance_ids`          | map nama → EC2 ID |
| `instance_public_ips`   | map nama → public IP (bastion + master) |
| `instance_private_ips`  | map nama → private IP |
| `ssh_commands`          | helper SSH (public direct, private via `-J` jumphost lewat bastion) |

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

**Tanpa load balancer terpisah** — master public IP jadi endpoint k8s API & Rancher. Lihat section "AWS resources" di bawah.

## Network design

```
                       internet
                          │
            ┌─────────────┼─────────────┐
            ▼             ▼             ▼
       ┌─────────┐   ┌─────────┐   (NodePort)
       │ bastion │   │ master  │  k8s API :6443
       │ (pub)   │   │ (pub)   │  Rancher UI :443
       └────┬────┘   └────┬────┘  Apps :80/443
            │ssh -J       │
            ▼             ▼ intra-VPC
   ┌────────────────────────────────────┐
   │ PRIVATE subnets (multi-AZ)         │
   │  worker-be / worker-fe / worker-db │
   │  (+ optional gpu)                  │
   │       │                            │
   │       ▼ NAT GW → internet (egress) │
   └────────────────────────────────────┘
```

| Subnet     | Penghuni                       | Akses internet |
|------------|--------------------------------|----------------|
| Public     | Bastion, Master (public IP)    | In + Out via IGW |
| Private    | worker-be/fe/db, GPU           | Out only via NAT GW; in via bastion/master (intra-VPC) |

**Subnet & AZ count:**
- 2 public subnets (1 per AZ)
- 2 private subnets (1 per AZ)
- **Total: 4 subnet di 2 AZ**

**Pertimbangan:**
- Tanpa AWS NLB = hemat ~$16/bulan + LCU charges.
- Trade-off: master jadi single point of failure untuk control plane. Untuk POC OK; production sebaiknya tambah HA dengan NLB.
- NAT Gateway ~$32/bulan (single) atau ~$64/bulan (per-AZ HA). Toggle via `single_nat_gateway`.

## AWS resources yg dibuat

| Resource                                  | Jumlah |
|-------------------------------------------|--------|
| VPC                                       | 1      |
| Internet Gateway                          | 1      |
| Public Subnet                             | 2 (bastion + master, multi-AZ) |
| Private Subnet                            | 2 (workers + gpu, multi-AZ)    |
| NAT Gateway + EIP                         | 1 (default) atau 2 (HA per-AZ) |
| Route Tables + associations               | public 1 (→IGW) + private 1 (→NAT) |
| Security Group                            | 1      |
| EC2 Instance                              | 5 (atau 6 dgn GPU) |
