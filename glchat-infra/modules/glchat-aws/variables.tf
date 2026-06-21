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
  description = "CIDR untuk public subnets (1 per AZ). Semua EC2 ditaruh di public untuk simplicity."
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

# Instance type sesuai tabel "Minimum Server Setup" di README gl-sre-helm-charts.
# Disk size ikut default AMI (tidak di-customize di sini).
variable "instances" {
  description = "Map konfigurasi 4 node wajib untuk cluster GLChat standalone"
  type = map(object({
    instance_type = string
    role          = string
  }))

  default = {
    bastion = {
      instance_type = "t3.small"
      role          = "bastion"
    }
    loadbalancer = {
      instance_type = "t3.medium"
      role          = "loadbalancer"
    }
    master = {
      instance_type = "t3.xlarge"
      role          = "k8s-master"
    }
    worker = {
      instance_type = "t3.2xlarge"
      role          = "k8s-worker"
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
