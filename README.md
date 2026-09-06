# Multi-Region Disaster Recovery

Terraform-managed AWS infrastructure for surviving a regional outage with replicated data, encrypted traffic, automated health checks, and a tested failover process.

This is a portfolio and interview-preparation project. It demonstrates how to design, provision, test, and operate an active-passive disaster-recovery platform rather than only creating redundant resources.

## Overview

The platform runs an active application in Mumbai and a warm standby in N. Virginia. CloudFront sends normal traffic to the primary ALB and fails over to the secondary ALB when the primary origin returns configured failure responses. RDS PostgreSQL and S3 assets are replicated across regions. A Route 53 health check, CloudWatch alarm, SNS topic, and Lambda provide the database-promotion path.

**Regions:** `ap-south-1` (primary) · `us-east-1` (secondary)

**Topology:** Active-passive — secondary stays warm, promoted on failover

**Tech stack:** AWS, Terraform, Route 53, CloudFront, ACM, S3, RDS PostgreSQL, ALB, Auto Scaling, IAM, SNS, Lambda, CloudWatch

## Status

Complete — Day 14 of 14 done. The secure HTTPS origin rollout is deployed and both regional Route 53 health checks are passing. The split-brain guard is implemented and validated for the application-only outage path. See [PLAN.md](./docs/PLAN.md) for the day-by-day build plan and decisions.

## Architecture

```text
Client
	-> Route 53 alias: dr.cloudwithpreetham.in
	-> CloudFront origin group
			 -> Primary ALB (HTTPS, ap-south-1)
			 -> Secondary ALB (HTTPS, us-east-1)

Primary RDS PostgreSQL
	-> Cross-region read replica in us-east-1
Primary S3 assets
	-> S3 Cross-Region Replication

Primary HTTPS health check
	-> CloudWatch alarm
	-> SNS
	-> Lambda primary-DB guard
	-> Promote secondary RDS replica only when primary DB is down
```

For the maintained diagram and design rationale, see [docs/architecture/architecture.md](./docs/architecture/architecture.md).

## Repository Layout

| Path                        | Purpose                                                     |
| --------------------------- | ----------------------------------------------------------- |
| `terraform/modules/region/` | Reusable VPC, ALB, HTTPS, ASG, IAM, RDS, and S3 module      |
| `terraform/environments/`   | Primary and secondary region values                         |
| `terraform/global/`         | Route 53, CloudFront, failover alarm, SNS, and Lambda stack |
| `terraform/bootstrap/`      | S3 state bucket and DynamoDB lock-table bootstrap           |
| `docs/architecture/`        | Architecture diagram and design decisions                   |
| `docs/runbooks/`            | Failover, verification, and failback procedures             |
| `docs/dr-tests/`            | Test procedures and recorded results                        |
| `docs/hardening/`           | Security findings and remediation record                    |
| `docs/STAR.md`              | Interview-ready STAR explanation of the project             |

## Prerequisites

- AWS CLI authenticated to the target account
- Terraform `>= 1.5`
- Bash, including WSL on Windows
- An existing delegated DNS setup for `dr.cloudwithpreetham.in`
- Permission to create AWS networking, compute, storage, database, DNS, CDN, IAM, and monitoring resources

Review the values in `terraform/environments/*.tfvars` and `terraform/global/terraform.tfvars` before applying. Never commit credentials, passwords, or generated files.

## Getting Started

The regional stacks use separate remote-state keys. Apply the regions before the global stack because the global stack needs both ALB endpoints, while the secondary RDS replica needs the primary DB ARN.

```bash
cd terraform

# Primary region
./apply-region.sh primary

# Secondary region
./apply-region.sh secondary

# Global traffic and failover resources
cd global
terraform init -reconfigure -input=false
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

For an existing deployment, inspect every plan before applying. The helper script reconfigures the backend for the selected region and prints outputs needed by the other stack.

## Verify the Deployment

```bash
curl -I https://origin-primary.dr.cloudwithpreetham.in/health
curl -I https://origin-secondary.dr.cloudwithpreetham.in/health
curl -I https://dr.cloudwithpreetham.in/health
```

Expected result is HTTP `200` for all three endpoints. Verify the health checks and alarm as well:

```bash
aws route53 get-health-check-status \
	--health-check-id <primary-health-check-id> \
	--query 'HealthCheckObservations[*].[Region,StatusReport.Status]' \
	--output table

aws cloudwatch describe-alarms \
	--alarm-names multi-region-dr-primary-health-alarm \
	--region us-east-1 \
	--query 'MetricAlarms[0].[StateValue,ActionsEnabled]' \
	--output table
```

The expected alarm state is `OK` with actions enabled. For operational actions, use [docs/runbooks/failover-failback-runbook.md](./docs/runbooks/failover-failback-runbook.md), not ad-hoc promotion commands.

## Security and Cost Notes

- Client-to-CloudFront and CloudFront-to-ALB traffic use HTTPS with TLS 1.2 or better.
- RDS is private and accepts database traffic only from the application security group.
- The RDS master password is managed by AWS Secrets Manager and is not stored in Terraform state.
- The promotion Lambda uses narrowly scoped RDS permissions and refuses app-only promotion when the primary DB is healthy.
- This deployment creates billable resources, including NAT gateways, RDS instances, cross-region replication, and CloudFront. Destroy non-essential resources between practice sessions and check AWS billing.

## Measured Outcomes

- Traffic failover through CloudFront: seconds in the simulated outage test.
- Database promotion path: approximately 2.5 minutes, dominated by the three consecutive 60-second alarm evaluations.
- Controlled promotion data loss: zero after replication was drained to the recorded WAL cutoff.
- S3 test-object replication: approximately 36 seconds for a 21-byte object.

## Documentation

- [Build plan and decisions](./docs/PLAN.md)
- [Architecture and rationale](./docs/architecture/architecture.md)
- [Failover and failback runbook](./docs/runbooks/failover-failback-runbook.md)
- [Hardening record](./docs/hardening/high-findings-remediation.md)
- [STAR interview explanation](./docs/STAR.md)
