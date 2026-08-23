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
