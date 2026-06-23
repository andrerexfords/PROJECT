output "vpc_id" {
  description = "ID dari VPC yang dibuat"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block VPC"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "List ID public subnet (untuk bastion + master)"
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "List ID private subnet (untuk workers + gpu)"
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
  description = "Map nama instance -> public IP (bastion + master)"
  value       = { for k, v in module.ec2 : k => v.public_ip }
}

output "instance_private_ips" {
  description = "Map nama instance -> private IP"
  value       = { for k, v in module.ec2 : k => v.private_ip }
}

output "ssh_commands" {
  description = "Helper SSH: bastion/master direct, workers via -J jumphost"
  value = {
    for k, v in module.ec2 :
    k => v.public_ip != "" ? "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${v.public_ip}" : "ssh -i ~/.ssh/${var.key_name}.pem -J ubuntu@${try(module.ec2["bastion"].public_ip, "<bastion-public-ip>")} ubuntu@${v.private_ip}"
  }
}
