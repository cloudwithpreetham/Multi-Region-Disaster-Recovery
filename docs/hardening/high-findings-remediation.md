# Hardening — Closing the Two High-Severity Findings

This document turns the two High-severity items from the Day 12 review into concrete, ordered changes. Neither is a one-line edit — each has an interaction that will break the running failover if applied naively, so the gotchas are called out inline. Nothing here is applied; treat it as a plan to review with `terraform plan` before committing.

The two findings:

1. The ALB is internet-facing and HTTP-only, so CloudFront-to-origin traffic is cleartext and the ALB is reachable directly, bypassing CloudFront.
2. Replica promotion is triggered by application-tier health alone, with no check that the primary database is actually down — a split-brain waiting to happen (and exactly what the Day 12 test demonstrated).

## Finding 1 — Encrypt and lock down the ALB origin

The goal is TLS on the CloudFront-to-ALB hop and no direct public access to the ALB, without breaking the Route 53 health check. Three parts, and the order between them matters.

### 1a. HTTPS listener plus a regional ACM certificate

ACM is regional, so CloudFront's us-east-1 certificate does not cover the ALBs. Each app region needs its own certificate, validated via DNS in the `dr.cloudwithpreetham.in` zone. That zone lives in the `global` stack, so the region module needs the zone id passed in, along with a public origin hostname for the ALB (for example `origin-primary.dr.cloudwithpreetham.in` and `origin-secondary.dr.cloudwithpreetham.in`).

```hcl
# modules/region/variables.tf
variable "origin_domain_name" {
  description = "Public hostname for this region's ALB origin (e.g. origin-primary.dr.cloudwithpreetham.in). The ACM cert is issued and validated for this name."
  type        = string
}

variable "dns_zone_id" {
  description = "Route 53 zone id for dr.cloudwithpreetham.in, used for ACM DNS validation records"
  type        = string
}
```

```hcl
# modules/region/alb.tf — add
resource "aws_acm_certificate" "alb" {
  domain_name       = var.origin_domain_name
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}

resource "aws_route53_record" "alb_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.alb.domain_validation_options :
    dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
  zone_id = var.dns_zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "alb" {
  certificate_arn         = aws_acm_certificate.alb.arn
  validation_record_fqdns = [for r in aws_route53_record.alb_cert_validation : r.fqdn]
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.alb.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
```

Add an ALIAS record pointing `origin_domain_name` at this ALB, then repoint the CloudFront origins at that hostname over HTTPS:

```hcl
# global/main.tf — both custom_origin_config blocks
custom_origin_config {
  http_port              = 80
  https_port             = 443
  origin_protocol_policy = "https-only"   # was "http-only"
  origin_ssl_protocols   = ["TLSv1.2"]
}
```

### 1b. Restrict ALB ingress to CloudFront — but keep the health checker in

This is the trap. Locking the ALB security group to CloudFront's prefix list alone breaks the Route 53 health check: the health checkers are not in the CloudFront range, so once they can no longer reach `/health`, the alarm goes to ALARM and — because of Finding 2 — promotes the replica. You must allow both CloudFront and the Route 53 health-checker ranges.

```hcl
# modules/region/security_groups.tf — replace the two 0.0.0.0/0 ingress blocks on aws_security_group.alb

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# HTTPS from CloudFront only
ingress {
  description     = "HTTPS from CloudFront origin-facing"
  from_port       = 443
  to_port         = 443
  protocol        = "tcp"
  prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
}
```

The Route 53 health-checker IPs are not a managed prefix list; pull them from the published ranges. The health check currently runs on HTTP:80, so allow that port from those ranges:

```hcl
data "aws_ip_ranges" "route53_healthchecks" {
  services = ["route53_healthchecks"]
}

resource "aws_security_group_rule" "health_from_r53" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = data.aws_ip_ranges.route53_healthchecks.cidr_blocks
  description       = "Route 53 health checkers reaching /health on port 80"
}
```

The cleaner end state is to move the health check itself to HTTPS on 443 against `origin_domain_name`, then drop the port-80 exception and remove the HTTP listener entirely, closing cleartext completely. To do that, update `aws_route53_health_check.primary` and `.secondary` in `global/main.tf` to `type = "HTTPS"`, `port = 443`, and `fqdn = <origin hostname>`.

Sequencing is critical: ship the certificate, the HTTPS listener, and the health-check move first; confirm the check is green on 443; only then remove the HTTP:80 listener and the port-80 security-group rule. Reverse that order and you blackhole the health check and trip a false promotion.

## Finding 2 — Stop the split-brain by confirming the primary is down

The Lambda must check the primary database, not just whether it is itself still a replica. That needs the primary's identity and region, a slightly wider (but still scoped) IAM policy, and logic that promotes only when the primary is genuinely unreachable or in a failed state.

```hcl
# global/failover.tf — add primary identity to the Lambda environment
environment {
  variables = {
    SECONDARY_REGION        = var.secondary_region
    SECONDARY_DB_IDENTIFIER = local.secondary_db_identifier
    PRIMARY_REGION          = var.primary_region
    PRIMARY_DB_IDENTIFIER   = local.primary_db_identifier
  }
}
```

This requires a new `var.primary_db_arn` in the global stack (the primary's `db_arn` output, filled into `global/terraform.tfvars`), with `local.primary_db_identifier` parsed from it using the same `split(":", ...)` trick already used for the secondary.

```hcl
# widen the IAM policy — still only describe + promote, on two named instances
statement {
  actions = ["rds:DescribeDBInstances"]
  resources = [
    "arn:aws:rds:${var.secondary_region}:*:db:${local.secondary_db_identifier}",
    "arn:aws:rds:${var.primary_region}:*:db:${local.primary_db_identifier}",
  ]
}

statement {
  actions   = ["rds:PromoteReadReplica"]
  resources = ["arn:aws:rds:${var.secondary_region}:*:db:${local.secondary_db_identifier}"]
}
```

```python
# global/lambda/promote_replica.py
import os
import boto3
from botocore.exceptions import ClientError, EndpointConnectionError

SECONDARY_REGION = os.environ["SECONDARY_REGION"]
SECONDARY_DB_IDENTIFIER = os.environ["SECONDARY_DB_IDENTIFIER"]
PRIMARY_REGION = os.environ["PRIMARY_REGION"]
PRIMARY_DB_IDENTIFIER = os.environ["PRIMARY_DB_IDENTIFIER"]

# Instance states that mean the primary is not serving, so promotion is safe.
PRIMARY_DOWN_STATES = {
    "failed",
    "inaccessible-encryption-credentials",
    "incompatible-network",
    "restore-error",
    "storage-failure",
}


def primary_is_down():
    rds = boto3.client("rds", region_name=PRIMARY_REGION)
    try:
        inst = rds.describe_db_instances(
            DBInstanceIdentifier=PRIMARY_DB_IDENTIFIER
        )["DBInstances"][0]
    except rds.exceptions.DBInstanceNotFoundFault:
        return True  # primary is gone entirely
    except (EndpointConnectionError, ClientError):
        return True  # primary region or API unreachable — treat as down
    return inst["DBInstanceStatus"] in PRIMARY_DOWN_STATES


def handler(event, context):
    rds = boto3.client("rds", region_name=SECONDARY_REGION)

    replica = rds.describe_db_instances(
        DBInstanceIdentifier=SECONDARY_DB_IDENTIFIER
    )["DBInstances"][0]

    if not replica.get("ReadReplicaSourceDBInstanceIdentifier"):
        print(f"{SECONDARY_DB_IDENTIFIER} is not a replica (already promoted) — skipping.")
        return {"promoted": False, "reason": "not_a_replica"}

    if not primary_is_down():
        print("Primary DB still reachable and healthy — refusing to promote (would split-brain).")
        return {"promoted": False, "reason": "primary_healthy"}

    print(f"Primary confirmed down. Promoting {SECONDARY_DB_IDENTIFIER} in {SECONDARY_REGION}...")
    rds.promote_read_replica(DBInstanceIdentifier=SECONDARY_DB_IDENTIFIER)
    return {"promoted": True, "db_instance_identifier": SECONDARY_DB_IDENTIFIER}
```

The behavior change is deliberate. An application-tier-only failure — the ASG scaled to zero while the database is fine, which is precisely the Day 12 test — now returns `primary_healthy` and refuses to promote. CloudFront still fails the application tier over to the secondary region; the database is promoted only on a real primary-database loss. A regional API outage that makes `describe_db_instances` fail is treated as "down," which is correct.

After applying, re-run the Day 12 test and confirm the replica is now **not** promoted: the automatic promotion from that test should become a logged no-op with reason `primary_healthy`.

While in this file, also add the deferred Medium item: a Lambda dead-letter queue and a CloudWatch error alarm, so a refused or failed promotion is visible rather than silent.

## Apply order

Work one stack at a time and review each plan. Do Finding 2 first — it is self-contained and it makes Finding 1's health-check changes safe (a stray promotion during the listener/SG cutover can no longer split-brain). Then do Finding 1, following the 1a-before-1b sequencing above. Re-run the Day 12 failover test at the end to confirm both: the application still fails over via CloudFront, and the replica is no longer auto-promoted on an app-only outage.
