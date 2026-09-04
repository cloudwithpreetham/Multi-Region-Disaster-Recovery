# Failover / Failback Runbook — Multi-Region-Disaster-Recovery

Operator-facing procedure for a regional failure of the primary (`ap-south-1`), and for restoring the normal disaster-recovery posture afterward. This runbook consolidates the mechanics validated in the Day 12 failover test and the Day 13 controlled-promotion / data-integrity test into a single sequence you can follow under pressure.

**System:** `multi-region-dr`, AWS account `799997637340`.
**Primary region:** `ap-south-1` (Mumbai) · **Secondary region:** `us-east-1` (N. Virginia).
**Public endpoint:** `https://dr.cloudwithpreetham.in`.

## Component map

| Layer          | Primary (`ap-south-1`)                        | Secondary (`us-east-1`)                                                                                                                     | Failover behavior                                                                                                                                                                              |
| -------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Edge / traffic | —                                             | —                                                                                                                                           | CloudFront distribution with an origin group: primary ALB is the default origin, automatic failover to the secondary ALB on `500/502/503/504`. Route 53 alias points the domain at CloudFront. |
| Compute        | `multi-region-dr-primary-app-asg` (desired 2) | `multi-region-dr-secondary-app-asg` (desired 1, max 4, warm pool)                                                                           | Secondary stays warm; target-tracking + warm pool scale it out on load once it is serving.                                                                                                     |
| Data           | `multi-region-dr-primary-db` (writer)         | `multi-region-dr-secondary-db-replica` (cross-region read replica)                                                                          | Replica is promoted to a standalone writer on failover.                                                                                                                                        |
| Automation     | Route 53 health check on `/health`            | CloudWatch alarm `multi-region-dr-primary-health-alarm` (3×60s) → SNS → Lambda `multi-region-dr-promote-replica` → `rds:PromoteReadReplica` | Alarm, SNS, and Lambda all live in `us-east-1` because Route 53 health-check metrics only exist there.                                                                                         |

RDS engine is PostgreSQL 16.13; database `appdb`, master user `appadmin`, port `5432`, `sslmode=require`.

## Access and prerequisites

- **AWS CLI** configured for account `799997637340` (broad credentials on your workstation run the `describe-*`, `promote-read-replica`, and alarm-action calls).
- **Database access** is not reachable from a laptop: RDS is `publicly_accessible = false` and its security group admits the app-tier security group only. To run SQL, open a session into an app-tier instance in the relevant region and use it as a jump host:

  ```bash
  ID=$(aws ec2 describe-instances --region <region> \
    --filters "Name=tag:Role,Values=<primary|secondary>" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' --output text)
  aws ssm start-session --target "$ID" --region <region>
  # on the instance (Amazon Linux 2023 — client only, connects fine to the PG16 server):
  sudo dnf install -y postgresql15
  ```

- **Database credentials come from AWS Secrets Manager**, not from Terraform state. The master password is RDS-managed (`manage_master_user_password = true`), so it is never stored in `terraform.tfstate`. Retrieve it only when needed, into a hidden variable:

  ```bash
  SECRET_ARN=$(aws rds describe-db-instances --db-instance-identifier multi-region-dr-primary-db \
    --region ap-south-1 --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text)
  export PGPASSWORD=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" \
    --region ap-south-1 --query SecretString --output text | jq -r .password)
  ```

  Do not echo the value or leave it exported on a shared instance longer than necessary.

## Detection — is this a real regional failure?

Confirm the trigger before acting. The automation reacts to the primary's `/health` check; distinguish the three cases:

1. **Full primary regional outage** — the intended failover case. Primary ALB, app tier, and DB are all unreachable from `ap-south-1`. CloudFront serves from the secondary; the alarm fires and the Lambda promotes the replica.
2. **Application-tier-only outage** (app down, primary DB still healthy) — this is the split-brain hazard. See the warning below; the automation will still promote the replica even though the primary DB is fine.
3. **Transient blip** — a single failed check. The alarm requires 3 consecutive failed minutes precisely to avoid promoting on a blip; do not intervene manually for a single failed check.

Quick checks:

```bash
# public endpoint (should stay 200 even mid-failover, served from secondary)
curl -s -o /dev/null -w "%{http_code}\n" https://dr.cloudwithpreetham.in/health
curl -sI https://dr.cloudwithpreetham.in/health | grep -i x-cache

# alarm state
aws cloudwatch describe-alarms --alarm-names multi-region-dr-primary-health-alarm \
  --region us-east-1 --query 'MetricAlarms[0].StateValue'

# is the replica still a replica, and how far behind?
aws rds describe-db-instances --db-instance-identifier multi-region-dr-secondary-db-replica \
  --region us-east-1 --query 'DBInstances[0].[StatusInfos,ReadReplicaSourceDBInstanceIdentifier]'
```

> **Split-brain warning (High finding 2, not yet remediated).** The promotion Lambda triggers on app-tier health alone; it does **not** check whether the primary database is actually down. In an application-only outage the primary DB stays writable while the replica is promoted, so two writers can accept data and any writes taken by the primary during the window are discarded on failback. Until the `primary_healthy` guard in `docs/hardening/high-findings-remediation.md` is applied, before allowing or forcing a promotion confirm the primary DB is genuinely unreachable — not just the app tier. If only the app is down, prefer restoring the app tier over promoting.

## Failover procedure

### Step 1 — Traffic (automatic; verify only)

CloudFront's origin group fails traffic to the secondary ALB automatically on 5xx/timeout. No action is required. Verify the public endpoint returns `200` with `x-cache: Hit from cloudfront` (commands above). Measured behavior in the Day 12 test: the endpoint kept serving within seconds of the primary going away.

### Step 2 — Data (automatic, or manual if needed)

On a genuine primary outage the chain runs itself: health check fails → alarm reaches `ALARM` after 3×60s → SNS → Lambda promotes the replica. Observed end-to-end detection-to-promotion in Day 12 was on the order of 2.5 minutes. The Lambda is idempotent (it skips if the target is no longer a replica), so a flapping alarm will not error against an already-promoted instance.

If you must promote manually (automation disabled, or a controlled promotion), run the same API the Lambda calls:

```bash
aws rds promote-read-replica \
  --db-instance-identifier multi-region-dr-secondary-db-replica --region us-east-1
aws rds wait db-instance-available \
  --db-instance-identifier multi-region-dr-secondary-db-replica --region us-east-1
```

Promotion is **irreversible** — the instance becomes a standalone writer and stops replicating. The endpoint address does not change on promotion.

### Step 3 — Verify the promotion

```bash
aws rds describe-db-instances --db-instance-identifier multi-region-dr-secondary-db-replica \
  --region us-east-1 --query 'DBInstances[0].ReadReplicaSourceDBInstanceIdentifier'   # expect: null
```

From `psql` on the promoted instance, `SELECT pg_is_in_recovery();` should return `f`, and a test `INSERT` should succeed (a read replica would reject it with `cannot execute INSERT in a read-only transaction`). For a full data-integrity check — WAL cutoff, per-table row-count and content-hash comparison, zero-data-loss criterion — follow `docs/dr-tests/2026-09-02-day13-data-integrity.md`. Day 13 verified zero data loss when replication lag was drained to zero before a controlled promotion.

## Failback procedure — restoring the DR posture

The original primary in `ap-south-1` is authoritative and was never lost in a planned test. Failback rebuilds the `us-east-1` instance back into a read replica of the primary. This destroys the promoted instance (any writes taken on it after promotion are discarded) and recreates a fresh cross-region replica.

### Step 1 — Point Terraform at the secondary state, then replace the replica

```bash
cd terraform
terraform init -reconfigure -backend-config="key=multi-region-dr/secondary/terraform.tfstate"
terraform apply -replace='module.region.aws_db_instance.replica[0]' \
  -var-file=environments/secondary.tfvars
```

> If `apply` fails with `Error acquiring the state lock` / `ConditionalCheckFailedException`, a previous interrupted run left a stale lock in the DynamoDB table `multi-region-dr-tfstate-lock`. Confirm no other apply is running, then `terraform force-unlock <lock-id>` and re-run. This happened during the Day 13 test and cleared cleanly.

### Step 2 — Undo the safety changes and restore capacity

```bash
# restore the primary app tier to its normal sizing (see environments/primary.tfvars)
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name multi-region-dr-primary-app-asg \
  --min-size <prev> --desired-capacity <prev> --region ap-south-1

# re-enable the failover automation (if it was frozen for a controlled test)
aws cloudwatch enable-alarm-actions \
  --alarm-names multi-region-dr-primary-health-alarm --region us-east-1
```

### Step 3 — Confirm replication is healthy again

```bash
aws rds describe-db-instances --db-instance-identifier multi-region-dr-secondary-db-replica \
  --region us-east-1 --query 'DBInstances[0].[StatusInfos,ReadReplicaSourceDBInstanceIdentifier]'
```

Expect `StatusInfos[].Status = replicating`, `Normal = true`, a non-null source identifier, and `ReplicaLag` returning to its normal baseline before you call the system restored. The rebuilt replica may come up with a **new endpoint address**; if anything references the replica endpoint directly, reconcile it. In the Day 13 failback the endpoint happened to stay unchanged, but do not rely on that.

## Recovery objectives (measured, not just targeted)

- **RTO (traffic):** seconds — CloudFront origin failover is effectively immediate on 5xx/timeout.
- **RTO (database writer):** ~2.5 minutes — dominated by the deliberate 3×60s alarm threshold plus a few seconds of Lambda execution.
- **RPO:** approximately the replication lag at the moment of failure. At steady state cross-region `ReplicaLag` is typically single-digit to low-tens of seconds. In a controlled promotion where lag is drained to zero first, RPO is zero — Day 13 measured identical pre/post content hashes.

## Periodic DR-testing cadence

Testing is what keeps this runbook trustworthy. Run the following on a schedule; a monthly reminder is wired as a scheduled task, and each row points at the detailed procedure.

| Test                          | Frequency                             | What to do                                                                                                                                        | Pass criteria                                                            | Procedure                                                    |
| ----------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | ------------------------------------------------------------ |
| Replication health check      | Monthly                               | Confirm `StatusInfos = replicating` / `Normal = true` and read `ReplicaLag` from CloudWatch. Read-only, no promotion.                             | Replicating, lag within normal baseline.                                 | Part 1 of `docs/dr-tests/2026-09-02-day13-data-integrity.md` |
| Failover game-day             | Quarterly (Jan / Apr / Jul / Oct)     | Simulate a primary outage (scale primary ASG to 0 or trip the health check), confirm CloudFront failover and automated promotion, then fail back. | Endpoint stays 200; promotion completes; failback restores steady state. | `docs/dr-tests/2026-09-01-day12-failover-test.md`            |
| Data-integrity promotion test | Semi-annual                           | Controlled promotion with a known WAL cutoff; compare per-table row counts and content hashes across the promotion.                               | Zero data loss vs cutoff; promoted instance writable.                    | `docs/dr-tests/2026-09-02-day13-promotion-test.md`           |
| Runbook & credential review   | Annual                                | Re-read this runbook against the live system for drift; rotate the RDS master password (now an RDS/Secrets Manager rotation).                     | Runbook accurate; secret rotated.                                        | This document                                                |
| Targeted re-test              | After any change to the failover path | Re-run whichever test covers the changed component.                                                                                               | As per the affected test.                                                | —                                                            |

After High finding 2 is remediated, re-run the failover game-day: an application-only outage should then leave the replica untouched (the `primary_healthy` guard makes promotion a no-op), while a genuine primary-DB loss still promotes.

## References

- Failover test (Day 12): `docs/dr-tests/2026-09-01-day12-failover-test.md`
- Controlled-promotion runbook + results (Day 13): `docs/dr-tests/2026-09-02-day13-promotion-test.md`
- Data-integrity procedure (Day 13 companion): `docs/dr-tests/2026-09-02-day13-data-integrity.md`
- Open hardening findings (split-brain guard, HTTPS origin): `docs/hardening/high-findings-remediation.md`
- Architecture and decision rationale: `docs/architecture/architecture.md`
