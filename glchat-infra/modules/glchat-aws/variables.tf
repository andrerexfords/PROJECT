variable "aws_region" {
  description = "AWS region untuk semua resource"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Nama project untuk naming & tagging"
  type        = string
  default     = "glchat"
}

variable "environment" {
  description = "Environment (dev/staging/prod/standalone)"
  type        = string
  default     = "standalone"
}

# ---------- Network ----------

variable "vpc_cidr" {
  description = "CIDR block untuk VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR untuk public subnets (1 per AZ). NLB butuh minimal 2 AZ untuk HA."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "allowed_ssh_cidr" {
  description = "CIDR yang boleh SSH (port 22). GANTI ke IP kantor/rumah supaya tidak open ke seluruh internet."
  type        = string
  default     = "0.0.0.0/0"
}

# ---------- Compute ----------

variable "key_name" {
  description = "Nama EC2 key pair yang sudah ada di AWS region target"
  type        = string
}

variable "ami_id" {
  description = "AMI ID — Debian 12 atau Ubuntu 22.04 LTS+ (sesuai spec upstream gl-sre-helm-charts)"
  type        = string
}

variable "include_gpu" {
  description = "Provision GPU worker (default false — sesuai Task 2: GPU di-exclude by default)"
  type        = bool
  default     = false
}

# Cluster layout:
#   bastion     - control center (SSH jumphost, bukan k8s node)
#   master      - k8s control plane (RKE2)
#   worker-be   - backend workloads
#   worker-fe   - frontend workloads
#   worker-db   - database workloads (akan di-taint)
# (no load balancer EC2 — pakai AWS NLB)
variable "instances" {
  description = "Map konfigurasi EC2 (bastion + master + worker-be/fe/db)"
  type = map(object({
    instance_type = string
    role          = string
  }))

  default = {
    bastion = {
      instance_type = "t3.small"
      role          = "bastion"
    }
    master = {
      instance_type = "t3.xlarge"
      role          = "k8s-master"
    }
    worker-be = {
      instance_type = "t3.2xlarge"
      role          = "k8s-worker-backend"
    }
    worker-fe = {
      instance_type = "t3.2xlarge"
      role          = "k8s-worker-frontend"
    }
    worker-db = {
      instance_type = "t3.2xlarge"
      role          = "k8s-worker-database"
    }
  }
}

variable "gpu_instance" {
  description = "Konfigurasi GPU worker (dipakai kalau include_gpu = true)"
  type = object({
    instance_type = string
    role          = string
  })

  default = {
    instance_type = "g4dn.xlarge"
    role          = "k8s-worker-gpu"
  }
}

# ---------- Load Balancer (AWS NLB) ----------

variable "enable_load_balancer" {
  description = "Provision AWS NLB di depan worker nodes (untuk ingress) & master (untuk API)"
  type        = bool
  default     = true
}
