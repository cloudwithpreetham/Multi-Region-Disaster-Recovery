"""
Triggered by an SNS notification from a CloudWatch alarm watching the
primary region's Route53 health check. Promotes the secondary region's
RDS read replica to a standalone writer.

This is a one-way operation — once promoted, the replica stops
replicating and becomes an independent database. Re-establishing
replication back to a recovered primary is a manual failback step,
not something this function attempts (see Day 12-14 runbook work).
"""
import os
import boto3

# Secondary's RDS instance lives in a different region than this
# Lambda — the client must target that region explicitly, it isn't
# inferred from where the function itself runs.
SECONDARY_REGION = os.environ["SECONDARY_REGION"]
SECONDARY_DB_IDENTIFIER = os.environ["SECONDARY_DB_IDENTIFIER"]


def handler(event, context):
    rds = boto3.client("rds", region_name=SECONDARY_REGION)

    # Idempotency guard — if the alarm fires more than once (flapping,
    # retries), don't attempt a second promotion against an
    # already-promoted (no longer a replica) instance.
    instance = rds.describe_db_instances(
        DBInstanceIdentifier=SECONDARY_DB_IDENTIFIER
    )["DBInstances"][0]

    if not instance.get("ReadReplicaSourceDBInstanceIdentifier"):
        print(f"{SECONDARY_DB_IDENTIFIER} is not currently a read replica "
              f"(already promoted, or never was one) — skipping.")
        return {"promoted": False, "reason": "not_a_replica"}

    print(f"Promoting {SECONDARY_DB_IDENTIFIER} in {SECONDARY_REGION}...")
    rds.promote_read_replica(DBInstanceIdentifier=SECONDARY_DB_IDENTIFIER)

    return {"promoted": True, "db_instance_identifier": SECONDARY_DB_IDENTIFIER}
