region     = "ap-south-1"
is_primary = true

vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
replication_destination_bucket_arn = "arn:aws:s3:::multi-region-dr-secondary-assets-93001a4e"
