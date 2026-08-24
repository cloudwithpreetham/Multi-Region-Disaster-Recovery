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

variable "tags" {
  description = "Extra tags merged onto every resource in this module"
  type        = map(string)
  default     = {}
}
