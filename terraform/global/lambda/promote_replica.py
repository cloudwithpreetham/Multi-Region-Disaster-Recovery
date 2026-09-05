"""
Triggered by an SNS notification from a CloudWatch alarm watching the
primary region's Route53 health check. Promotes the secondary region's
RDS read replica to a standalone writer — but ONLY after confirming the
primary database itself is actually down.

Day 12's outage test exposed a split-brain bug: the alarm fires on
*application-tier* health alone (ALB targets, not the database), so an
app-only outage — the ASG scaled to zero while RDS is perfectly fine —
used to promote the replica anyway, leaving two independently-writable
databases. This version checks the primary DB's own status before
promoting; an app-tier failure with a healthy primary now refuses to
promote (CloudFront still fails traffic over, just not the database).

This is a one-way operation — once promoted, the replica stops
replicating and becomes an independent database. Re-establishing
replication back to a recovered primary is a manual failback step,
not something this function attempts (see the failover/failback
runbook).
"""
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
        print(f"{SECONDARY_DB_IDENTIFIER} is not a replica (already "
              f"promoted) — skipping.")
        return {"promoted": False, "reason": "not_a_replica"}

    if not primary_is_down():
        print("Primary DB still reachable and healthy — refusing to "
              "promote (would split-brain).")
        return {"promoted": False, "reason": "primary_healthy"}

    print(f"Primary confirmed down. Promoting {SECONDARY_DB_IDENTIFIER} "
          f"in {SECONDARY_REGION}...")
    rds.promote_read_replica(DBInstanceIdentifier=SECONDARY_DB_IDENTIFIER)

    return {"promoted": True, "db_instance_identifier": SECONDARY_DB_IDENTIFIER}
