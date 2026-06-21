output "vpc_id" {
  description = "ID dari VPC yang dibuat"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block VPC"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "List ID public subnet"
  value       = module.vpc.public_subnets
}

output "security_group_id" {
  description = "ID security group cluster"
  value       = aws_security_group.glchat.id
}

output "instance_ids" {
  description = "Map nama instance -> EC2 instance ID"
  value       = { for k, v in module.ec2 : k => v.id }
}

output "instance_public_ips" {
  description = "Map nama instance -> public IP"
  value       = { for k, v in module.ec2 : k => v.public_ip }
}

output "instance_private_ips" {
  description = "Map nama instance -> private IP"
  value       = { for k, v in module.ec2 : k => v.private_ip }
}

output "ssh_commands" {
  description = "Helper: command SSH per instance (assume default user ubuntu/admin)"
  value       = { for k, v in module.ec2 : k => "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${v.public_ip}" }
}
