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
}

# ---------- VPC + Subnets + IGW ----------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${local.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs            = slice(data.aws_availability_zones.available.names, 0, length(var.public_subnet_cidrs))
  public_subnets = var.public_subnet_cidrs

  enable_dns_hostnames = true
  enable_dns_support   = true

  map_public_ip_on_launch = true

  tags = local.common_tags
}

# ---------- Security Group ----------

resource "aws_security_group" "glchat" {
  name        = "${local.name_prefix}-sg"
  description = "Security group cluster GLChat standalone (bastion + LB + k8s)"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH (restricted)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS (Rancher UI + apps)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP (LB / Let's Encrypt)"
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
    description = "Allow all egress"
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

  ami                         = var.ami_id
  instance_type               = each.value.instance_type
  key_name                    = var.key_name
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.glchat.id]
  associate_public_ip_address = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${each.key}"
    Role = each.value.role
  })
}
