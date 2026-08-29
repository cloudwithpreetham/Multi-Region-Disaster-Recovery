# Architecture

## Topology

![Active-passive multi-region topology](../images/active-passive-topology.png)

Active-passive: `ap-south-1` serves all live traffic under normal operation. `us-east-1` stays warm with minimal Auto Scaling capacity and an RDS read replica, promoted only on failover. Route53 health checks monitor the primary; failure triggers Route53 failover routing to the secondary, with the RDS replica promoted to writer as part of the failover procedure.

Rejected active-active: adds data-consistency and write-conflict complexity, plus continuous double-cost, without a hard zero-downtime requirement to justify it. Active-passive also pairs naturally with Route53 failover routing (Phase 5).

## Regions

- **Primary:** `ap-south-1` (Mumbai) — lowest latency for testing/dev
- **Secondary:** `us-east-1` (N. Virginia) — cheapest cross-region data transfer, broadest service parity, most-documented region for troubleshooting

**Rationale:** Serve users from the nearest region, fail over to a well-supported, low-cost global fallback region when the primary is unavailable.

## Terraform Module Structure

One shared `terraform/modules/region` module, consumed via `terraform/environments/primary.tfvars` and `terraform/environments/secondary.tfvars`, with an `is_primary` flag toggling ASG size and RDS writer-vs-replica behavior. Global Route53/CloudFront resources live outside the module, since they're not per-region.

## Data Replication Strategy

**RDS:** Postgres 16 (major-version-only, avoids hardcoding a minor that can go stale) with a cross-region read replica. Primary generates its own master password via Terraform; the replica inherits credentials automatically — no password field on the replica resource. Cross-region encrypted replicas require an explicit `kms_key_id` in the replica's own region; `storage_encrypted = true` alone isn't accepted. `backup_retention_period = 1` on the primary is the one resource in this project that stays on even between destroy/rebuild sessions, since cross-region replicas require source backups enabled.

**S3:** A versioned assets bucket in each region (versioning is required on both source and destination for CRR), with Cross-Region Replication configured on the primary's bucket via a dedicated IAM role. Newer AWS replication schema requires an explicit `delete_marker_replication` block (set to `Disabled` here). Measured lag: a 21-byte test object replicated primary → secondary in ~36 seconds — acceptable for static/user-asset use.

**Apply-order dependency:** RDS and S3 replication pull the region apply order in opposite directions — the RDS replica needs primary's `db_arn` (primary first), while the S3 replication config needs secondary's bucket ARN (secondary first). Resolved by gating the S3 replication resources on the destination ARN being set, so primary's first apply just creates its bucket; a second primary apply (after secondary exists) attaches the actual replication rule.

## Traffic Routing

**Domain:** `dr.cloudwithpreetham.in`, a subdomain of the live `cloudwithpreetham.in` (registered at GoDaddy) delegated to a dedicated Route53 hosted zone via NS records — keeps this project's DNS fully isolated from the live domain rather than migrating the whole thing into Route53.

**Route53:** A single alias record points the subdomain straight at CloudFront. This replaced an earlier Day 8 design (dual latency-based A-records, one per region, each with its own health check) once CloudFront's origin group took over as the actual failover mechanism — two records doing the same job as one origin group was redundant. The two per-region health checks were kept anyway: useful standalone, and feed Day 10's RDS-promotion trigger.

**CloudFront:** Sits in front of both regions via an origin group — primary ALB is the default origin, with automatic failover to the secondary ALB on 500/502/503/504 responses. Requires an ACM certificate in `us-east-1` specifically (an AWS platform requirement for CloudFront, unrelated to where either app region actually is), DNS-validated through records in the same hosted zone. Cache behavior uses a short default TTL (60s, max 300s) since this is dynamic app traffic being fronted, not static assets — verified via `x-cache: Hit from cloudfront` on repeat requests.

**terraform/global/:** Both Route53 and CloudFront live in their own standalone Terraform stack, separate from `modules/region`, because they need both regions' ALB DNS name/zone ID simultaneously — a different dependency shape than the sequential single-ARN-passing used for RDS (Day 6) and S3 replication (Day 7).

## Failover Process

_(Route53 failover policy, RDS promotion automation — Day 10-11)_
