output "vpc_id" {
  value = module.region.vpc_id
}

output "public_subnet_ids" {
  value = module.region.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.region.private_subnet_ids
}

output "alb_security_group_id" {
  value = module.region.alb_security_group_id
}

output "app_security_group_id" {
  value = module.region.app_security_group_id
}

output "rds_security_group_id" {
  value = module.region.rds_security_group_id
}

output "alb_dns_name" {
  value = module.region.alb_dns_name
}

output "alb_zone_id" {
  value = module.region.alb_zone_id
}

output "asg_name" {
  value = module.region.asg_name
}

output "db_arn" {
  value = module.region.db_arn
}

output "db_endpoint" {
  value     = module.region.db_endpoint
  sensitive = true
}
