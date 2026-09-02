resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-${local.role}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${local.role}-db-subnet-group"
  })
}

# Only the primary generates its own credentials — a cross-region read
# replica inherits master username/password from the source instance
# automatically, so replicas never set username/password themselves.
resource "random_password" "db" {
  count = var.is_primary ? 1 : 0

  length  = 20
  special = false # avoids characters RDS master passwords reject
}

resource "aws_db_instance" "primary" {
  count = var.is_primary ? 1 : 0

  identifier     = "${var.project_name}-${local.role}-db"
  engine         = var.db_engine
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage      = var.db_allocated_storage
  storage_encrypted      = true
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.db[0].result
  port                   = var.db_port
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  multi_az            = false # cost trade-off — see AGENT.md cost-awareness note
  skip_final_snapshot = true  # portfolio project, torn down between sessions

  # Cross-region read replicas require automated backups enabled on
  # the source — this is the one thing that can't be zero here even
  # though everything else is destroy-between-sessions.
  backup_retention_period = 1

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${local.role}-db"
    Role = "primary"
  })
}

# Cross-region encrypted replicas need an explicit KMS key IN THE
# REPLICA'S OWN REGION — storage_encrypted = true alone isn't enough,
# AWS rejects the create otherwise even though the source is encrypted.
# Using the region's default AWS-managed RDS key rather than a custom
# CMK — no extra cost, no separate key management for this project.
data "aws_kms_key" "rds" {
  count  = var.is_primary ? 0 : 1
  key_id = "alias/aws/rds"
}

resource "aws_db_instance" "replica" {
  count = var.is_primary ? 0 : 1

  identifier          = "${var.project_name}-${local.role}-db-replica"
  replicate_source_db = var.primary_db_arn
  instance_class      = var.db_instance_class

  storage_encrypted      = true
  kms_key_id             = data.aws_kms_key.rds[0].arn
  port                   = var.db_port
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  multi_az            = false
  skip_final_snapshot = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${local.role}-db-replica"
    Role = "replica"
  })
}
