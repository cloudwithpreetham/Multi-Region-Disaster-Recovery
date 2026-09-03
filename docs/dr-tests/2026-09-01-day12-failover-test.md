# Multi-Region Disaster Recovery — Day 12 Failover Test Report

**Date:** 2026-09-01
**System:** `multi-region-dr` (AWS account 799997637340)
**Regions:** Primary `ap-south-1` · Secondary `us-east-1`
**Test type:** Simulated primary application-tier outage with automated failover and manual failback
**Result:** PASS — failover chain executed end to end; DR posture restored.

## 1. Summary

The primary application tier was taken offline by scaling its Auto Scaling Group to zero in `ap-south-1`. CloudFront origin failover kept the public endpoint (`https://dr.cloudwithpreetham.in`) serving within seconds. The automated data-tier failover chain — Route 53 health check → CloudWatch alarm → SNS → Lambda — detected the outage in roughly two and a half minutes and promoted the `us-east-1` read replica to a standalone primary. Failback then restored the primary application tier and rebuilt the secondary read replica. The end state was verified healthy on all three checks (replica re-established, alarm `OK`, endpoint `200`).

The dominant contributor to data-tier recovery time was the CloudWatch alarm's three-datapoint evaluation window (~3 minutes of detection latency).

## 2. Architecture under test

The edge is a CloudFront distribution fronting the public endpoint `https://dr.cloudwithpreetham.in`, configured with an origin group that fails over from the primary ALB to the secondary ALB. Route 53 hosted zone `Z03897481STG9N8OBDG3A` holds a health check against each region's ALB `/health` path.

The failover automation is: the primary ALB health check feeds the CloudWatch alarm `multi-region-dr-primary-health-alarm`, which publishes to the SNS topic `multi-region-dr-failover-alerts`, which invokes the Lambda `multi-region-dr-promote-replica`, which promotes the RDS read replica.

The data tier is PostgreSQL 16.13 on RDS: the primary instance `multi-region-dr-primary-db` in `ap-south-1`, with a cross-region read replica `multi-region-dr-secondary-db-replica` in `us-east-1`.

## 3. Method

The outage was simulated by scaling the primary application ASG to zero (`asg_min_size`, `asg_max_size`, `asg_desired_capacity` all `0`) via Terraform. With no healthy targets behind the primary ALB, the primary Route 53 health check fails, which drives the failover chain.

Note that this exercises the application-tier failover path. The primary RDS instance itself remained running throughout — see the split-brain observation in Section 6.

## 4. Timeline (UTC, 2026-08-24)

| Time                | Event                                                                                                                                                                             |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 16:56:34            | Terraform apply scaled the primary ASG to 0. Health poll started; first probe returned `000`.                                                                                     |
| 16:56:34 – 16:56:53 | Public endpoint intermittent (`000`/`200`) for ~19 s while primary ALB targets drained and CloudFront failed over to the secondary origin.                                        |
| 16:56:53 onward     | Endpoint stable at `200`, served via CloudFront (`x-cache: Hit from cloudfront`).                                                                                                 |
| 16:57:00 – 16:59:00 | `multi-region-dr-primary-health-alarm` recorded three datapoints of `0.0` (below threshold `1.0`) — primary ALB health check failing.                                             |
| ~16:59:00           | Alarm transitioned to `ALARM` on the third datapoint.                                                                                                                             |
| ~16:59 – 17:00      | SNS notified the Lambda. `multi-region-dr-promote-replica` invoked: _"Promoting multi-region-dr-secondary-db-replica in us-east-1..."_, reported duration 3263 ms.                |
| ~17:00+             | RDS promotion completed in the background; the replica became a standalone instance.                                                                                              |
| Failback            | Terraform apply restored the primary ASG (1 changed).                                                                                                                             |
| Failback            | Terraform `apply -replace` on the replica rebuilt it as a read replica of the primary (1 added, 1 destroyed), scoped with `-target` to avoid an unrelated launch-template change. |
| Verify              | Replica `available` with source = primary; alarm `OK`; endpoint `200`.                                                                                                            |

## 5. Results and recovery times

Application-tier recovery was effectively seconds. The public endpoint saw about 19 seconds of intermittent `000` responses while the primary ALB targets drained, then settled to a stable `200` served from the secondary region via CloudFront origin failover — transparent to any client that retries.

Data-tier detection took roughly two and a half minutes, from outage injection at 16:56:34 to the alarm firing at 16:59:00. This latency is governed entirely by the alarm's three-datapoint, sixty-second evaluation.

Data-tier promotion was fast once triggered: the Lambda's promote call returned in 3.26 seconds, though the full RDS promotion (the instance reboot to standalone) completes minutes afterward.

All links in the chain were confirmed to have fired — the Route 53 health check, the CloudWatch alarm, the SNS notification, and the Lambda promotion — verified through the alarm state history and the Lambda's CloudWatch logs.

## 6. Notable observations

**Split-brain during a partial outage.** Because this test scaled only the application ASG, the primary RDS instance in `ap-south-1` stayed up and writable. When the Lambda promoted the secondary replica, the system briefly held two independent writable databases. In a true full-region outage the primary database would also be unavailable, so this split-brain would not arise; it is an artifact of the application-only simulation rather than a defect. It did, however, mean that failback required rebuilding the replica (destroying the promoted standalone and recreating it as a replica of the primary), which discards any writes made to the promoted instance during the test window.

**An early RDS check misread the state.** An RDS `describe-db-instances` run at approximately 16:57 — before the alarm crossed its three-datapoint threshold at 16:59 — still showed the instance as a replica, which initially looked like a failure of the chain. It had simply been checked before the Lambda fired. The Lambda logs later confirmed the promotion executed correctly.

**Launch-template AMI drift.** During failback, `terraform plan` showed the secondary launch template's AMI drifting (`ami-0cb4805a67d37bd33` → `ami-0fe74bfcad4fd6bd2`) because the `aws_ami` data source resolves the most recent image. The failback apply was scoped to the replica only (`-target`) to avoid an unintended AMI change.

## 7. Recommendations

Tune detection latency. If the data-tier recovery-time objective is under about three minutes, reduce the alarm to two datapoints or a shorter period, balancing that against the risk of false-positive promotions.

Add a promotion guard. Gate the Lambda so it promotes only when the primary database is confirmed unreachable, avoiding the split-brain seen in a partial (application-only) outage.

Automate failback. The replica rebuild is currently a manual `terraform -replace`; capture it as a documented runbook or build target so recovery is not improvised.

Resolve the AMI strategy. Either pin the application AMI or roll it intentionally, so incidental drift does not surface during failover operations.

Consider write-fencing on the promoted secondary until the primary is confirmed down.

## 8. End state

The primary region (`ap-south-1`) has its application ASG restored and the RDS primary healthy and canonical. The secondary region (`us-east-1`) has a fresh read replica of the primary, status `available` and replicating. The `multi-region-dr-primary-health-alarm` is `OK` and the public endpoint returns `200`. DR posture is fully restored.

## Appendix — key resources

AWS account 799997637340.

- Public endpoint (CloudFront): `https://dr.cloudwithpreetham.in`
- Route 53 hosted zone: `Z03897481STG9N8OBDG3A`
  - Primary health check: `feb6b59b-d2c7-43c6-a8cc-59bac9c5ce44` (primary ALB `/health`)
  - Secondary health check: `f96fada0-89f2-4ab6-8417-b6bb5cc57de8`
- CloudWatch alarm: `multi-region-dr-primary-health-alarm` (`us-east-1`)
- SNS topic: `arn:aws:sns:us-east-1:799997637340:multi-region-dr-failover-alerts`
- Lambda: `multi-region-dr-promote-replica`
- Primary DB: `multi-region-dr-primary-db` (`ap-south-1`)
- Secondary replica: `multi-region-dr-secondary-db-replica` (`us-east-1`)
- Primary ALB: `multi-region-dr-primary-alb-1951686545.ap-south-1`
- Secondary ALB: `multi-region-dr-secondary-alb-840972268.us-east-1`

## Appendix — commands

Inject the outage (from `terraform/`, primary state):

```bash
terraform init -reconfigure -backend-config="key=multi-region-dr/primary/terraform.tfstate"
terraform apply -var-file=environments/primary.tfvars \
  -var="asg_min_size=0" -var="asg_max_size=0" -var="asg_desired_capacity=0"
```

Poll the endpoint with timestamps:

```bash
while true; do date -u; curl -s -o /dev/null -w "%{http_code}\n" https://dr.cloudwithpreetham.in/health; sleep 5; done
```

Watch the promotion:

```bash
aws rds describe-db-instances --db-instance-identifier multi-region-dr-secondary-db-replica \
  --region us-east-1 \
  --query 'DBInstances[0].[DBInstanceStatus,ReadReplicaSourceDBInstanceIdentifier]'
```

Failback — restore the primary application tier:

```bash
terraform init -reconfigure -backend-config="key=multi-region-dr/primary/terraform.tfstate"
terraform apply -var-file=environments/primary.tfvars
```

Failback — rebuild the replica (secondary state):

```bash
terraform init -reconfigure -backend-config="key=multi-region-dr/secondary/terraform.tfstate"
terraform plan -replace='module.region.aws_db_instance.replica[0]' \
  -target='module.region.aws_db_instance.replica[0]' \
  -var-file=environments/secondary.tfvars -out=failback.tfplan
terraform apply failback.tfplan
```

Verify the end state:

```bash
aws rds describe-db-instances --db-instance-identifier multi-region-dr-secondary-db-replica \
  --region us-east-1 \
  --query 'DBInstances[0].[DBInstanceStatus,ReadReplicaSourceDBInstanceIdentifier]'
aws cloudwatch describe-alarms --alarm-names multi-region-dr-primary-health-alarm \
  --region us-east-1 --query 'MetricAlarms[0].StateValue'
curl -s -o /dev/null -w "%{http_code}\n" https://dr.cloudwithpreetham.in/health
```
