# Architecture

## Topology

_(Diagram + active-active vs active-passive decision — Day 2)_

## Regions

- **Primary:** `ap-south-1` (Mumbai) — lowest latency for testing/dev
- **Secondary:** `us-east-1` (N. Virginia) — cheapest cross-region data transfer, broadest service parity, most-documented region for troubleshooting

**Rationale:** Serve users from the nearest region, fail over to a well-supported, low-cost global fallback region when the primary is unavailable.

## Terraform Module Structure

_(To be defined — Day 2)_

## Data Replication Strategy

_(RDS cross-region replica / Aurora Global Database, S3 CRR — Day 6-7)_

## Traffic Routing

_(Route53 + CloudFront design — Day 8-9)_

## Failover Process

_(Route53 failover policy, RDS promotion automation — Day 10-11)_
