variable "region" {
  description = "AWS region this instance of the module deploys into"
  type        = string
}

variable "is_primary" {
  description = "Whether this region is the active primary (true) or the warm standby (false)"
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

variable "availability_zone_count" {
  description = "Number of AZs to spread public/private subnets across"
  type        = number
  default     = 2
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per AZ"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets, one per AZ"
  type        = list(string)
}

variable "app_port" {
  description = "Port the application listens on behind the ALB"
  type        = number
  default     = 8080
}

variable "db_port" {
  description = "Port the database listens on"
  type        = number
  default     = 5432
}

variable "health_check_path" {
  description = "Path the ALB target group health-checks against"
  type        = string
  default     = "/health"
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

variable "scale_target_cpu" {
  description = "Target average CPU utilization (%) for the target-tracking scaling policy"
  type        = number
  default     = 50
}

variable "enable_warm_pool" {
  description = "Enable a warm pool of pre-initialized stopped instances — meaningful for the standby region so a Day 10 promotion doesn't wait on a cold scale-out"
  type        = bool
  default     = false
}

variable "warm_pool_min_size" {
  description = "Minimum stopped instances to keep pre-initialized in the warm pool"
  type        = number
  default     = 0
}

variable "tags" {
  description = "Extra tags merged onto every resource in this module"
  type        = map(string)
  default     = {}
}

variable "db_engine" {
  description = "RDS engine"
  type        = string
  default     = "postgres"
}

variable "db_engine_version" {
  description = "RDS engine version (major-version-only lets AWS pick the latest supported minor, avoiding this going stale)"
  type        = string
  default     = "16"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB for the primary DB instance"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Initial database name (primary only — replicas inherit it)"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username (primary only — replicas inherit credentials)"
  type        = string
  default     = "appadmin"
}

variable "primary_db_arn" {
  description = "ARN of the primary region's RDS instance. Required when is_primary = false — grab it from the primary apply's db_arn output and pass it via this region's tfvars."
  type        = string
  default     = null
}

variable "assets_bucket_prefix" {
  description = "Prefix for the S3 assets bucket name (a random suffix is appended for global uniqueness)"
  type        = string
  default     = "assets"
}

variable "replication_destination_bucket_arn" {
  description = "ARN of the secondary region's assets bucket. Required when is_primary = true — apply secondary first, grab it from that apply's assets_bucket_arn output, and pass it via primary's tfvars."
  type        = string
  default     = null
}
