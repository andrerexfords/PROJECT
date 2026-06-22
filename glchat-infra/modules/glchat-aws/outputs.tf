output "vpc_id" {
  description = "ID dari VPC yang dibuat"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block VPC"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "List ID public subnet (untuk NLB + bastion)"
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "List ID private subnet (untuk k8s master + workers)"
  value       = module.vpc.private_subnets
}

output "nat_gateway_ips" {
  description = "Elastic IP NAT Gateway(s) — outbound IP private subnet ke internet"
  value       = module.vpc.nat_public_ips
}

output "security_group_id" {
  description = "ID security group cluster"
  value       = aws_security_group.glchat.id
}

# ---------- EC2 ----------

output "instance_ids" {
  description = "Map nama instance -> EC2 instance ID"
  value       = { for k, v in module.ec2 : k => v.id }
}

output "instance_public_ips" {
  description = "Map nama instance -> public IP (hanya bastion yg punya public IP)"
  value       = { for k, v in module.ec2 : k => v.public_ip }
}

output "instance_private_ips" {
  description = "Map nama instance -> private IP"
  value       = { for k, v in module.ec2 : k => v.private_ip }
}

output "ssh_commands" {
  description = "Helper SSH: bastion via public IP, sisanya via bastion (-J jumphost)"
  value = {
    for k, v in module.ec2 :
    k => v.public_ip != "" ? "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${v.public_ip}" : "ssh -i ~/.ssh/${var.key_name}.pem -J ubuntu@${try(module.ec2["bastion"].public_ip, "<bastion-public-ip>")} ubuntu@${v.private_ip}"
  }
}

# ---------- NLB ----------

output "nlb_dns_name" {
  description = "DNS name AWS NLB (jadi server_name di config.yml upstream)"
  value       = var.enable_load_balancer ? aws_lb.glchat[0].dns_name : null
}

output "nlb_zone_id" {
  description = "Route53 hosted zone ID NLB (untuk alias record)"
  value       = var.enable_load_balancer ? aws_lb.glchat[0].zone_id : null
}

output "nlb_arn" {
  description = "ARN NLB"
  value       = var.enable_load_balancer ? aws_lb.glchat[0].arn : null
}
