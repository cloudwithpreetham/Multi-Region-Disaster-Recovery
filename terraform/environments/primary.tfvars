region     = "ap-south-1"
is_primary = true

vpc_cidr                           = "10.0.0.0/16"
public_subnet_cidrs                = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs               = ["10.0.11.0/24", "10.0.12.0/24"]
replication_destination_bucket_arn = "arn:aws:s3:::multi-region-dr-secondary-assets-a800585e"
origin_domain_name                 = "origin-primary.dr.cloudwithpreetham.in"
dns_zone_id                        = "Z03897481STG9N8OBDG3A"
asg_min_size                       = 2
asg_desired_capacity               = 2
asg_max_size                       = 3
