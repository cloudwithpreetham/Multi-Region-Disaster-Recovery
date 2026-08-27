# PLAN.md — Multi-Region-Disaster-Recovery Build Plan

Day-by-day roadmap for building a Terraform-codified, multi-region AWS high-availability architecture — the goal is a system that survives a full regional outage with replicated data, automated traffic routing, and a tested failover process.

**Legend:** ⬜ Not started · 🟨 In progress · ✅ Done

---

## Phase 1 — Multi-Region Architecture Design

| Day | Task                                                                                                                                         | Status | Notes / Decisions                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Select primary & secondary AWS regions; document rationale (latency, compliance, cost)                                                       | ✅     | Primary: `ap-south-1` (Mumbai) — lowest latency for testing/dev. Secondary: `us-east-1` (N. Virginia) — cheapest cross-region option, broadest service parity, most-documented region for troubleshooting. Real-world pattern: serve local users from nearest region, fail over to us-east-1 as the resilient, well-supported fallback.                                                                                                                                                                                                                                                                       |
| 2   | Decide active-active vs active-passive topology based on RTO requirements; sketch topology diagram; define shared Terraform module structure | ✅     | Topology: active-passive — secondary (us-east-1) stays warm with minimal ASG capacity and an RDS read replica, promoted only on failover. Chosen over active-active for simplicity, lower cost, and natural fit with Route53 failover routing (Phase 5). Module structure: one shared `terraform/modules/region` module, consumed via `terraform/environments/primary.tfvars` and `terraform/environments/secondary.tfvars` with an `is_primary` flag toggling ASG size / RDS writer-vs-replica behavior; global Route53/CloudFront resources live outside the module. Diagram added to docs/architecture.md. |

## Phase 2 — Regional Infrastructure Provisioning

| Day | Task                                                                                                                            | Status | Notes / Decisions                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| --- | ------------------------------------------------------------------------------------------------------------------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 3   | Write shared Terraform module: VPC, subnets, security groups                                                                    | ✅     | `terraform/modules/region` built: VPC, 2 public + 2 private subnets across AZs, IGW, single NAT gateway (cost trade-off, not an AZ-failover concern), public/private route tables. 3-tier security group chain: ALB (80/443 from internet) → app (app_port from ALB SG) → RDS (db_port from app SG). Root config (`terraform/main.tf`/`providers.tf`/`variables.tf`) wires the module, with `terraform/environments/primary.tfvars` (ap-south-1, 10.0.0.0/16) and `terraform/environments/secondary.tfvars` (us-east-1, 10.1.0.0/16, non-overlapping CIDR for future VPC peering). State is local for now — remote backend lands Day 5. Terraform config moved under `terraform/` to keep root clean alongside `docs/`. |
| 4   | Add ALB + Auto Scaling Group to module; deploy to Region 1                                                                      | 🟨     | `terraform/modules/region` gets `alb.tf` (internet-facing ALB, target group on `app_port`, HTTP:80 listener — HTTPS/ACM deferred until CloudFront) and `asg.tf` (launch template on latest AL2023 AMI, placeholder health-check user-data, ASG in private subnets sized via `asg_min/max/desired`). Root wires new `instance_type`/`asg_*` vars through. Not yet applied to Region 1 — deploy/verify still pending.                                                                                                                                                                                              |
| 5   | Deploy same module to Region 2 via separate `.tfvars` + remote state; verify symmetry; configure IAM roles / cross-region trust | ✅     | Remote state migrated to S3 + DynamoDB (partial backend config, region-scoped state keys via `-backend-config="key=..."`). Secondary applied and verified symmetric with primary. IAM role + instance profile (SSM, CloudWatch) added to modules/region, attached to launch template, re-verified healthy in primary. S3 cross-region replication trust deferred to Day 6 — no buckets exist yet to scope it to. |

## Phase 3 — Data Replication

| Day | Task                                                                                           | Status | Notes / Decisions |
| --- | ---------------------------------------------------------------------------------------------- | ------ | ----------------- |
| 6   | Set up RDS with cross-region read replica (or Aurora Global Database)                          | ✅     | Chose RDS Postgres cross-region read replica over Aurora Global DB — simpler, cheaper, fits portfolio scope. `rds.tf` added to modules/region: db subnet group, primary instance (auto-generated password via `random_password`, `backup_retention_period = 1` — the one thing that can't be zero even with destroy-between-sessions, since cross-region replicas require source backups enabled), replica (inherits credentials automatically, no password field). `engine_version` set to major-version-only (`"16"`) after `16.4` came back stale/unsupported. Replica needed an explicit `kms_key_id` in its own region — `storage_encrypted = true` alone wasn't enough for AWS to accept a cross-region encrypted replica. Two-step apply: primary first, copy its `db_arn` output into secondary's tfvars as `primary_db_arn`, then apply secondary. Both applied clean, replica came up `available`, ALB health checks still `ok` in both regions. |
| 7   | Enable S3 Cross-Region Replication for static/user assets; document acceptable replication lag | ✅     | `s3.tf` added to modules/region: assets bucket in both regions (versioning required on both sides for CRR), public access fully blocked. Replication IAM role + policy + `aws_s3_bucket_replication_configuration` gated on `is_primary && replication_destination_bucket_arn != null` — lets primary's first apply create just the bucket, with the actual replication config attached in a second pass once secondary's bucket ARN is known. **True circular dependency discovered**: secondary's RDS replica needs primary's `db_arn` (primary first), but primary's S3 replication config needs secondary's bucket ARN (secondary first) — resolved via a 3-step apply: primary (RDS+bucket, no replication config) → secondary (RDS replica+bucket) → primary again (attach replication config). Also hit `DeleteMarkerReplication must be specified` — newer S3 CRR schema requires an explicit `delete_marker_replication { status = "Disabled" }` block, fixed. **Measured lag:** small test object (21 bytes) replicated primary → secondary in ~36 seconds — well within CRR's typical seconds-to-low-minutes range, acceptable for this project's static/user-asset use case. |

## Phase 4 — Global Traffic Routing

| Day | Task                                                                                                  | Status | Notes / Decisions |
| --- | ----------------------------------------------------------------------------------------------------- | ------ | ----------------- |
| 8   | Configure Route53 latency-based or geolocation routing across both ALBs; add per-region health checks | ⬜     |                   |
| 9   | Deploy CloudFront in front of both regions; verify edge caching and origin failover                   | ⬜     |                   |

## Phase 5 — Failover Automation & Health Checks

| Day | Task                                                                                 | Status | Notes / Decisions |
| --- | ------------------------------------------------------------------------------------ | ------ | ----------------- |
| 10  | Configure Route53 failover routing policy; automate RDS replica promotion            | ⬜     |                   |
| 11  | Pre-warm or tune secondary-region Auto Scaling capacity for fast failover absorption | ⬜     |                   |

## Phase 6 — Testing & Documentation

| Day | Task                                                                                                                           | Status | Notes / Decisions |
| --- | ------------------------------------------------------------------------------------------------------------------------------ | ------ | ----------------- |
| 12  | Run simulated regional outage (kill primary ALB health check / shut down Region 1); measure actual failover time vs target RTO | ⬜     |                   |
| 13  | Verify data integrity and application functionality post-failover in secondary region                                          | ⬜     |                   |
| 14  | Write failover/failback runbook; finalize architecture diagram; define periodic DR-testing cadence                             | ⬜     |                   |

---

## Key Deliverable

A Terraform-codified, multi-region AWS architecture with replicated data, health-check-driven Route53/CloudFront failover, and a tested regional-outage runbook.

## Decision Log

_(Append architecture decisions here as they're made — include the alternative considered and why it was rejected. This is the section interviewers will probe hardest.)_

- **Region pair:** Primary `ap-south-1` (Mumbai), Secondary `us-east-1` (N. Virginia). Chosen over an all-same-continent pair for a realistic "serve local, fail over to a well-supported global fallback" pattern. us-east-1 specifically picked for cheapest cross-region data transfer and broadest service/documentation support, useful when troubleshooting.
- **Topology:** Active-passive over active-active. Rejected active-active due to added complexity (data consistency, conflict resolution) and continuous double-cost for a portfolio project where zero-downtime failover isn't a hard requirement. Active-passive also pairs naturally with Route53 failover routing planned for Phase 5.
- **Terraform structure:** Single shared `terraform/modules/region` module parameterized by an `is_primary` flag, consumed via separate `.tfvars` per environment, rather than duplicating resource definitions per region — keeps both regions guaranteed symmetric and avoids drift.
- **Directory layout:** All Terraform config (root files, `modules/`, `environments/`) moved under `terraform/`, separate from `docs/` at the repo root — keeps the two concerns from mixing as the repo grows.
- **NAT gateway:** One NAT gateway per region (not one per AZ). Rejected per-AZ NAT for cost — this project's DR story is about surviving a regional outage, not an AZ outage, so losing egress in one AZ if that AZ has an issue is an acceptable trade-off here.
- **CIDR allocation:** Primary uses `10.0.0.0/16`, secondary uses `10.1.0.0/16` — chosen deliberately non-overlapping now so VPC peering (needed for cross-region RDS replication and any direct-connect asset sync in Phase 3) doesn't require re-addressing later.
- **S3 replication apply order:** Discovered a real circular dependency between Day 6 and Day 7 — secondary's RDS replica needs primary's `db_arn`, but primary's S3 replication config needs secondary's bucket ARN. Resolved by gating the replication config resources on the destination ARN being non-null, so primary can be applied once without it (just creates the bucket), then re-applied after secondary exists to attach the actual replication rule.
-

## Cost / Teardown Notes

_(Log any resources left running between sessions, and teardown reminders here.)_

-
