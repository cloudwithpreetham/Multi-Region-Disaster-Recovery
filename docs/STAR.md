# Multi-Region Disaster Recovery - STAR Story

## Short Interview Answer

### Situation

The application was vulnerable to a regional outage because it depended on a single AWS region. A regional failure could make the application unavailable, lose access to the database, and require slow manual recovery. The project also needed to demonstrate a practical recovery process with measurable RTO and RPO rather than only provisioning redundant resources.

### Task

I needed to design and implement an active-passive, multi-region disaster-recovery platform on AWS. The solution had to replicate application data, route traffic to a healthy region, promote the secondary database during a genuine primary failure, protect against split-brain, and provide a tested failover and failback runbook.

### Action

I implemented the platform with Terraform using one reusable regional module and separate primary and secondary configurations.

- Deployed matching VPC, subnet, security-group, ALB, and Auto Scaling infrastructure in `ap-south-1` and `us-east-1`.
- Used an encrypted Amazon RDS PostgreSQL cross-region read replica for database recovery.
- Configured Amazon S3 Cross-Region Replication for application assets.
- Put Amazon CloudFront in front of both regional ALBs with an origin failover group.
- Added regional ACM certificates, Route 53 DNS aliases, HTTPS ALB listeners, HTTPS-only CloudFront origins, and HTTPS Route 53 health checks.
- Added a CloudWatch alarm, SNS notification path, and Lambda automation for replica promotion.
- Restricted the Lambda IAM policy to the required RDS describe and promote actions.
- Added a primary database health gate to the Lambda. If the primary DB is still healthy, the Lambda returns `primary_healthy` and refuses promotion, preventing split-brain during an application-only outage.
- Added Lambda dead-letter handling and an error alarm so failed promotion attempts are visible.
- Tuned the secondary Auto Scaling Group with target tracking and a warm pool for faster failover absorption.
- Migrated the RDS master password to AWS Secrets Manager instead of keeping it in Terraform state.
- Documented detection, failover, verification, failback, RTO, RPO, and recurring DR tests in an operator runbook.

### Result

The platform was validated through live AWS tests:

- The public HTTPS endpoint returned HTTP 200 through CloudFront.
- Both regional HTTPS health checks returned successful HTTP 200 responses.
- A simulated primary application-tier outage kept public traffic available through CloudFront while the database guard correctly refused promotion because the primary DB remained healthy.
- A controlled promotion verified zero data loss at a drained replication cutoff, and the promoted database accepted writes.
- Failback rebuilt the secondary as a read replica and restored the normal DR posture.
- Measured traffic recovery was within seconds, while database-writer recovery was approximately 2.5 minutes, primarily due to the three-consecutive-minute alarm threshold.
- The final architecture provides an automated, encrypted, health-driven regional recovery path with documented operational procedures.

## Technical Talking Points

- **Architecture:** Active-passive across Mumbai (`ap-south-1`) and N. Virginia (`us-east-1`).
- **Traffic failover:** CloudFront origin group with the primary ALB first and the secondary ALB as failover.
- **Database failover:** RDS PostgreSQL read replica promoted to a standalone writer by Lambda.
- **Split-brain control:** Promotion occurs only when the secondary is still a replica and the primary DB is absent or in an accepted failed state.
- **Security:** HTTPS from the client to CloudFront and from CloudFront to each ALB; regional ACM certificates; private RDS; least-privilege Lambda IAM; Secrets Manager-managed credentials.
- **Infrastructure as code:** One shared Terraform module with region-specific `.tfvars` files and separate remote state keys.
- **Availability trade-off:** Active-passive was selected over active-active to reduce cost and data-conflict complexity while meeting the project's recovery goals.
- **Cost trade-off:** One NAT gateway per region and a lower secondary baseline reduce standby cost; the secondary warm pool and higher maximum capacity improve failover readiness.

## Metrics to Quote

- **Traffic RTO:** seconds through CloudFront origin failover.
- **Database promotion RTO:** approximately 2.5 minutes in the tested configuration.
- **RPO:** approximately the cross-region replication lag; zero in the controlled test after draining replication to the WAL cutoff.
- **Data-integrity result:** matching row counts and content hashes after controlled promotion.
- **Failover threshold:** three consecutive 60-second health failures before automated promotion.

## Honest Limitation

The app-only outage path was validated live and confirmed that the split-brain guard refuses promotion. A full live regional database-loss promotion should be tested separately under a controlled change window because RDS promotion is irreversible and requires rebuilding replication during failback.
