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
  #   - bastion       → public subnet  (SSH dari internet via allowed_ssh_cidr)
  #   - master, worker-*, gpu → private subnet (no public IP, akses via bastion / NLB)
  public_instances = ["bastion"]

  master_keys = [for k, v in local.instances_to_create : k if can(regex("master", k))]
  worker_keys = [for k, v in local.instances_to_create : k if can(regex("worker|gpu", k))]
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

  # SSH dari allowed_ssh_cidr ke bastion (workers di private subnet, jadi tidak reachable dari internet bahkan dgn rule ini).
  ingress {
    description = "SSH (effective hanya untuk bastion di public subnet)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # k8s API & HTTP/HTTPS — NLB forward ke target (workers di private subnet pakai source IP client).
  ingress {
    description = "Kubernetes API (via NLB)"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS (via NLB → ingress controller)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP (via NLB → ingress / LetsEncrypt)"
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

  # Bastion → public subnet + public IP. Worker/master → private subnet, no public IP.
  subnet_id                   = contains(local.public_instances, each.key) ? module.vpc.public_subnets[0] : module.vpc.private_subnets[0]
  associate_public_ip_address = contains(local.public_instances, each.key)

  vpc_security_group_ids = [aws_security_group.glchat.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${each.key}"
    Role = each.value.role
  })
}

# ---------- AWS NLB (Network Load Balancer) ----------
# NLB di public subnet (internet-facing), target di private subnet — pola standard.
#   - Listener 6443 (TCP) → master(s)     k8s API
#   - Listener 443  (TCP) → workers       ingress HTTPS
#   - Listener 80   (TCP) → workers       ingress HTTP / LetsEncrypt HTTP-01

resource "aws_lb" "glchat" {
  count = var.enable_load_balancer ? 1 : 0

  name               = "${local.name_prefix}-nlb"
  load_balancer_type = "network"
  subnets            = module.vpc.public_subnets
  internal           = false

  enable_cross_zone_load_balancing = true

  tags = local.common_tags
}

# --- API target group (6443 → masters) ---

resource "aws_lb_target_group" "api" {
  count = var.enable_load_balancer ? 1 : 0

  name        = substr("${local.name_prefix}-api", 0, 32)
  port        = 6443
  protocol    = "TCP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = "6443"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = local.common_tags
}

resource "aws_lb_target_group_attachment" "api" {
  for_each = var.enable_load_balancer ? toset(local.master_keys) : toset([])

  target_group_arn = aws_lb_target_group.api[0].arn
  target_id        = module.ec2[each.value].id
  port             = 6443
}

resource "aws_lb_listener" "api" {
  count = var.enable_load_balancer ? 1 : 0

  load_balancer_arn = aws_lb.glchat[0].arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api[0].arn
  }
}

# --- HTTPS target group (443 → workers) ---

resource "aws_lb_target_group" "https" {
  count = var.enable_load_balancer ? 1 : 0

  name        = substr("${local.name_prefix}-https", 0, 32)
  port        = 443
  protocol    = "TCP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = "443"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = local.common_tags
}

resource "aws_lb_target_group_attachment" "https" {
  for_each = var.enable_load_balancer ? toset(local.worker_keys) : toset([])

  target_group_arn = aws_lb_target_group.https[0].arn
  target_id        = module.ec2[each.value].id
  port             = 443
}

resource "aws_lb_listener" "https" {
  count = var.enable_load_balancer ? 1 : 0

  load_balancer_arn = aws_lb.glchat[0].arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https[0].arn
  }
}

# --- HTTP target group (80 → workers) ---

resource "aws_lb_target_group" "http" {
  count = var.enable_load_balancer ? 1 : 0

  name        = substr("${local.name_prefix}-http", 0, 32)
  port        = 80
  protocol    = "TCP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = "80"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = local.common_tags
}

resource "aws_lb_target_group_attachment" "http" {
  for_each = var.enable_load_balancer ? toset(local.worker_keys) : toset([])

  target_group_arn = aws_lb_target_group.http[0].arn
  target_id        = module.ec2[each.value].id
  port             = 80
}

resource "aws_lb_listener" "http" {
  count = var.enable_load_balancer ? 1 : 0

  load_balancer_arn = aws_lb.glchat[0].arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http[0].arn
  }
}
