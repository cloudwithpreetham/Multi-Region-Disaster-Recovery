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

output "alb_dns_name" {
  description = "Public DNS name of this region's ALB (Route53 target, Phase 4)"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of this region's ALB (for Route53 alias records)"
  value       = aws_lb.this.zone_id
}

output "asg_name" {
  description = "Name of this region's app-tier Auto Scaling Group"
  value       = aws_autoscaling_group.app.name
}

output "db_arn" {
  description = "ARN of this region's RDS instance (primary's ARN feeds the replica's primary_db_arn var; replica has no separate ARN needed elsewhere)"
  value       = var.is_primary ? aws_db_instance.primary[0].arn : aws_db_instance.replica[0].arn
}

output "db_endpoint" {
  description = "Connection endpoint for this region's RDS instance (primary or replica)"
  value       = var.is_primary ? aws_db_instance.primary[0].endpoint : aws_db_instance.replica[0].endpoint
}

output "assets_bucket_arn" {
  description = "ARN of this region's assets bucket. Secondary's is needed by primary's replication_destination_bucket_arn var — apply secondary first."
  value       = aws_s3_bucket.assets.arn
}

output "assets_bucket_name" {
  description = "Name of this region's assets bucket"
  value       = aws_s3_bucket.assets.bucket
}
