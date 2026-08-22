# PLAN.md — multi-region-disaster-recovery Build Plan

Day-by-day roadmap for building a Terraform-codified, multi-region AWS high-availability architecture — the goal is a system that survives a full regional outage with replicated data, automated traffic routing, and a tested failover process.

**Legend:** ⬜ Not started · 🟨 In progress · ✅ Done

---

## Phase 1 — Multi-Region Architecture Design

| Day | Task                                                                                                                                         | Status | Notes / Decisions                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Select primary & secondary AWS regions; document rationale (latency, compliance, cost)                                                       | ✅     | Primary: `ap-south-1` (Mumbai) — lowest latency for testing/dev. Secondary: `us-east-1` (N. Virginia) — cheapest cross-region option, broadest service parity, most-documented region for troubleshooting. Real-world pattern: serve local users from nearest region, fail over to us-east-1 as the resilient, well-supported fallback.                                                                                                                                                                                                                                         |
| 2   | Decide active-active vs active-passive topology based on RTO requirements; sketch topology diagram; define shared Terraform module structure | ✅     | Topology: active-passive — secondary (us-east-1) stays warm with minimal ASG capacity and an RDS read replica, promoted only on failover. Chosen over active-active for simplicity, lower cost, and natural fit with Route53 failover routing (Phase 5). Module structure: one shared `modules/region` module, consumed via `environments/primary.tfvars` and `environments/secondary.tfvars` with an `is_primary` flag toggling ASG size / RDS writer-vs-replica behavior; global Route53/CloudFront resources live outside the module. Diagram added to docs/architecture.md. |

## Phase 2 — Regional Infrastructure Provisioning

| Day | Task                                                                                                                            | Status | Notes / Decisions |
| --- | ------------------------------------------------------------------------------------------------------------------------------- | ------ | ----------------- |
| 3   | Write shared Terraform module: VPC, subnets, security groups                                                                    | ⬜     |                   |
| 4   | Add ALB + Auto Scaling Group to module; deploy to Region 1                                                                      | ⬜     |                   |
| 5   | Deploy same module to Region 2 via separate `.tfvars` + remote state; verify symmetry; configure IAM roles / cross-region trust | ⬜     |                   |

## Phase 3 — Data Replication

| Day | Task                                                                                           | Status | Notes / Decisions |
| --- | ---------------------------------------------------------------------------------------------- | ------ | ----------------- |
| 6   | Set up RDS with cross-region read replica (or Aurora Global Database)                          | ⬜     |                   |
| 7   | Enable S3 Cross-Region Replication for static/user assets; document acceptable replication lag | ⬜     |                   |

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
- **Terraform structure:** Single shared `modules/region` module parameterized by an `is_primary` flag, consumed via separate `.tfvars` per environment, rather than duplicating resource definitions per region — keeps both regions guaranteed symmetric and avoids drift.
-

## Cost / Teardown Notes

_(Log any resources left running between sessions, and teardown reminders here.)_

-
