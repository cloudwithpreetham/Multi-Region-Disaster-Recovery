module "region" {
  source = "./modules/region"

  region               = var.region
  is_primary           = var.is_primary
  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  instance_type        = var.instance_type
  asg_min_size         = var.asg_min_size
  asg_max_size         = var.asg_max_size
  asg_desired_capacity = var.asg_desired_capacity

  scale_target_cpu   = var.scale_target_cpu
  enable_warm_pool   = var.enable_warm_pool
  warm_pool_min_size = var.warm_pool_min_size

  primary_db_arn = var.primary_db_arn

  replication_destination_bucket_arn = var.replication_destination_bucket_arn
}
