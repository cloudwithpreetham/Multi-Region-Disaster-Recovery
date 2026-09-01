region     = "us-east-1"
is_primary = false

# Non-overlapping with primary's 10.0.0.0/16 — required for the VPC peering
# that cross-region RDS replication (Day 6) and asset sync will ride on.
vpc_cidr             = "10.1.0.0/16"
public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.11.0/24", "10.1.12.0/24"]
primary_db_arn = "arn:aws:rds:ap-south-1:799997637340:db:multi-region-dr-primary-db"

# Day 11: warm standby tuning — lower baseline than primary to save
# cost day-to-day, but max headroom raised so it can absorb full
# production load once Day 10 promotes it. Warm pool keeps stopped
# instances pre-initialized so scale-out after promotion is fast,
# not a cold multi-minute boot cycle.
asg_min_size         = 1
asg_desired_capacity = 1
asg_max_size          = 4
enable_warm_pool      = true
warm_pool_min_size    = 1
