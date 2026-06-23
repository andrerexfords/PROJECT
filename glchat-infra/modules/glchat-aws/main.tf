data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "glchat-aws"
  }

  instances_to_create = var.include_gpu ? merge(var.instances, { gpu = var.gpu_instance }) : var.instances

  # Instance placement:
  #   - bastion → public subnet (SSH dari internet via allowed_ssh_cidr)
  #   - master  → public subnet (jadi endpoint k8s API & Rancher karena tidak pakai NLB)
  #   - workers (be/fe/db/gpu) → private subnet (no public IP, akses via bastion / master)
  public_instances = ["bastion", "master"]
}

# ---------- VPC + Subnets + IGW + NAT GW ----------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${local.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, length(var.public_subnet_cidrs))
  public_subnets  = var.public_subnet_cidrs
  private_subnets = var.private_subnet_cidrs

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  tags = local.common_tags
}

# ---------- Security Group ----------

resource "aws_security_group" "glchat" {
  name        = "${local.name_prefix}-sg"
  description = "Security group cluster GLChat standalone"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH (bastion + master di public subnet)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "Kubernetes API (langsung ke master public IP)"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS (Rancher UI + apps via ingress controller di master/worker)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP (LetsEncrypt HTTP-01 / ingress)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Intra-cluster (all ports)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow all egress (private nodes via NAT GW)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# ---------- EC2 Instances ----------

module "ec2" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 5.6"

  for_each = local.instances_to_create

  name = "${local.name_prefix}-${each.key}"

  ami           = var.ami_id
  instance_type = each.value.instance_type
  key_name      = var.key_name

  # bastion + master → public subnet + public IP. Worker/gpu → private subnet, no public IP.
  subnet_id                   = contains(local.public_instances, each.key) ? module.vpc.public_subnets[0] : module.vpc.private_subnets[0]
  associate_public_ip_address = contains(local.public_instances, each.key)

  vpc_security_group_ids = [aws_security_group.glchat.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${each.key}"
    Role = each.value.role
  })
}
