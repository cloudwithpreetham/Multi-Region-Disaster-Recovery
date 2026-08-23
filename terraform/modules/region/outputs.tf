output "vpc_id" {
  description = "ID of this region's VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of this region's VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "alb_security_group_id" {
  description = "Security group ID for the ALB (Day 4 will attach this)"
  value       = aws_security_group.alb.id
}

output "app_security_group_id" {
  description = "Security group ID for the app tier / Auto Scaling Group (Day 4 will attach this)"
  value       = aws_security_group.app.id
}

output "rds_security_group_id" {
  description = "Security group ID for RDS (Day 6 will attach this)"
  value       = aws_security_group.rds.id
}
