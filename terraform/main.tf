module "region" {
  source = "./modules/region"

  region               = var.region
  is_primary           = var.is_primary
  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}
