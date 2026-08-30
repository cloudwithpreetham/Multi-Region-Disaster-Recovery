terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Own state file — this isn't per-region, it needs both regions'
  # ALB info at once, unlike everything in modules/region so far.
  backend "s3" {
    bucket         = "multi-region-dr-tfstate-d6c9434f"
    key            = "multi-region-dr/global/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "multi-region-dr-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-south-1" # Route53 is a global service, region here just picks the API endpoint
}

# ACM requires certificates for CloudFront to live in us-east-1
# specifically — an AWS platform requirement, unrelated to where
# either of our two app regions actually are.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

variable "zone_name" {
  description = "Subdomain hosted zone to create — kept separate from the live cloudwithpreetham.in domain, delegated via NS records in GoDaddy"
  type        = string
  default     = "dr.cloudwithpreetham.in"
}

variable "primary_alb_dns_name" {
  description = "Primary region's ALB DNS name — from that region's alb_dns_name output"
  type        = string
}

variable "primary_alb_zone_id" {
  description = "Primary region's ALB hosted zone ID — from that region's alb_zone_id output"
  type        = string
}

variable "primary_region" {
  description = "AWS region code for the primary ALB (latency routing policy needs this)"
  type        = string
  default     = "ap-south-1"
}

variable "secondary_alb_dns_name" {
  description = "Secondary region's ALB DNS name — from that region's alb_dns_name output"
  type        = string
}

variable "secondary_alb_zone_id" {
  description = "Secondary region's ALB hosted zone ID — from that region's alb_zone_id output"
  type        = string
}

variable "secondary_region" {
  description = "AWS region code for the secondary ALB"
  type        = string
  default     = "us-east-1"
}

resource "aws_route53_zone" "dr" {
  name = var.zone_name
}

# Health checks stand on their own here — Day 8's dual latency
# A-records that used to reference these were replaced by a single
# CloudFront alias (Day 9, below), since CloudFront's own origin
# group failover now does that job. Health checks are kept anyway:
# useful independently, and Day 10 wires one into the RDS-promotion
# trigger.
resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_alb_dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  request_interval  = 30
  failure_threshold = 3

  tags = {
    Name = "multi-region-dr-primary-health"
  }
}

resource "aws_route53_health_check" "secondary" {
  fqdn              = var.secondary_alb_dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  request_interval  = 30
  failure_threshold = 3

  tags = {
    Name = "multi-region-dr-secondary-health"
  }
}

# --- Day 9: CloudFront in front of both regions ---

resource "aws_acm_certificate" "cf" {
  provider = aws.us_east_1

  domain_name       = var.zone_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cf_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cf.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }

  zone_id = aws_route53_zone.dr.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "cf" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.cf.arn
  validation_record_fqdns = [for r in aws_route53_record.cf_cert_validation : r.fqdn]
}

resource "aws_cloudfront_distribution" "this" {
  enabled     = true
  aliases     = [var.zone_name]
  price_class = "PriceClass_All"

  origin_group {
    origin_id = "region-failover-group"

    failover_criteria {
      status_codes = [500, 502, 503, 504]
    }

    member {
      origin_id = "primary-alb"
    }

    member {
      origin_id = "secondary-alb"
    }
  }

  origin {
    origin_id   = "primary-alb"
    domain_name = var.primary_alb_dns_name

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "http-only" # ALB has no HTTPS listener yet
      origin_ssl_protocols     = ["TLSv1.2"]
    }
  }

  origin {
    origin_id   = "secondary-alb"
    domain_name = var.secondary_alb_dns_name

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "http-only"
      origin_ssl_protocols     = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "region-failover-group"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods         = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD"]

    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 60  # short TTL — this is dynamic app traffic, not static assets
    max_ttl     = 300
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cf.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name = "multi-region-dr-distribution"
  }
}

resource "aws_route53_record" "cloudfront" {
  zone_id = aws_route53_zone.dr.zone_id
  name    = var.zone_name
  type    = "A"

  alias {
    name = aws_cloudfront_distribution.this.domain_name
    # Fixed value AWS uses for every CloudFront distribution's hosted zone.
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
}

output "zone_id" {
  value = aws_route53_zone.dr.zone_id
}

output "name_servers" {
  description = "Add these as NS records for 'dr' in GoDaddy's DNS management to delegate the subdomain"
  value       = aws_route53_zone.dr.name_servers
}

output "cloudfront_domain_name" {
  description = "CloudFront's own *.cloudfront.net domain, useful for testing before/without the custom domain"
  value       = aws_cloudfront_distribution.this.domain_name
}
