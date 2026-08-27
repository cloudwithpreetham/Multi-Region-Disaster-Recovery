variable "region" {
  description = "AWS region to deploy into (set per environment via -var-file)"
  type        = string
}

variable "is_primary" {
  description = "Whether this deployment is the primary (true) or secondary/standby (false)"
  type        = bool
}

variable "project_name" {
  description = "Short project name used as a prefix for resource names/tags"
  type        = string
  default     = "multi-region-dr"
}

variable "vpc_cidr" {
  description = "CIDR block for this region's VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per AZ"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets, one per AZ"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type for app-tier ASG instances"
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  description = "Minimum instances in the app-tier Auto Scaling Group"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum instances in the app-tier Auto Scaling Group"
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Desired instances in the app-tier Auto Scaling Group"
  type        = number
  default     = 2
}

variable "primary_db_arn" {
  description = "ARN of primary region's RDS instance — only needed on the secondary apply, grabbed from primary's db_arn output"
  type        = string
  default     = null
}

variable "replication_destination_bucket_arn" {
  description = "ARN of secondary region's assets bucket — only needed on the primary apply, grabbed from secondary's assets_bucket_arn output"
  type        = string
  default     = null
}
