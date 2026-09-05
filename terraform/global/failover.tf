# --- Day 10: automated RDS replica promotion on primary failure ---
#
# Chain: Route53 health check (primary) -> CloudWatch alarm -> SNS ->
# Lambda -> rds:PromoteReadReplica on secondary.
#
# Route53 health check metrics only exist in us-east-1, regardless of
# which regions the health checks themselves monitor — same AWS
# platform quirk as ACM certs for CloudFront (Day 9).

variable "secondary_db_arn" {
  description = "Secondary region's RDS instance ARN — same value you already have from that region's db_arn output. The instance identifier is parsed out of it automatically, consistent with how every other cross-region reference in this project is passed."
  type        = string
}

variable "primary_db_arn" {
  description = "Primary region's RDS instance ARN — from that region's db_arn output. Needed so the Lambda can confirm the primary DB is actually down before promoting, not just that the ASG health check failed (Day 12 finding: app-tier-only outages were split-braining the database)."
  type        = string
}

locals {
  # ARN format: arn:aws:rds:region:account:db:identifier — identifier
  # is everything after the last colon.
  secondary_db_identifier = element(split(":", var.secondary_db_arn), length(split(":", var.secondary_db_arn)) - 1)
  primary_db_identifier   = element(split(":", var.primary_db_arn), length(split(":", var.primary_db_arn)) - 1)
}

variable "alert_email" {
  description = "Optional email to notify on failover. Leave null to skip the subscription — the Lambda promotion still fires regardless."
  type        = string
  default     = null
}

resource "aws_sns_topic" "failover" {
  provider = aws.us_east_1
  name     = "multi-region-dr-failover-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email != null ? 1 : 0

  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.failover.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "primary_health" {
  provider = aws.us_east_1

  alarm_name          = "multi-region-dr-primary-health-alarm"
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  dimensions          = { HealthCheckId = aws_route53_health_check.primary.id }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3 # 3 consecutive failed minutes before triggering — avoids a single blip promoting the replica
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching" # no data usually means the checker itself can't reach the endpoint — treat that as unhealthy too

  alarm_actions = [aws_sns_topic.failover.arn]

  alarm_description = "Primary region ALB health check failing — triggers automated secondary RDS replica promotion via Lambda"
}

data "archive_file" "promote_replica" {
  type        = "zip"
  source_file = "${path.module}/lambda/promote_replica.py"
  output_path = "${path.module}/lambda/promote_replica.zip"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  provider = aws.us_east_1

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "promote_replica" {
  provider = aws.us_east_1

  name               = "multi-region-dr-promote-replica-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "promote_replica_logs" {
  provider   = aws.us_east_1
  role       = aws_iam_role.promote_replica.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "promote_replica_dlq" {
  provider = aws.us_east_1

  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.promote_replica_dlq.arn]
  }
}

resource "aws_iam_role_policy" "promote_replica_dlq" {
  provider = aws.us_east_1

  name   = "multi-region-dr-promote-replica-dlq-policy"
  role   = aws_iam_role.promote_replica.id
  policy = data.aws_iam_policy_document.promote_replica_dlq.json
}

data "aws_iam_policy_document" "promote_replica" {
  provider = aws.us_east_1

  statement {
    # Describe both instances — the secondary for the idempotency
    # check, the primary to confirm it's genuinely down before
    # promoting (Finding 2 fix). Promote stays scoped to secondary only.
    actions = ["rds:DescribeDBInstances"]
    resources = [
      "arn:aws:rds:${var.secondary_region}:*:db:${local.secondary_db_identifier}",
      "arn:aws:rds:${var.primary_region}:*:db:${local.primary_db_identifier}",
    ]
  }

  statement {
    actions   = ["rds:PromoteReadReplica"]
    resources = ["arn:aws:rds:${var.secondary_region}:*:db:${local.secondary_db_identifier}"]
  }
}

resource "aws_iam_role_policy" "promote_replica" {
  provider = aws.us_east_1

  name   = "multi-region-dr-promote-replica-policy"
  role   = aws_iam_role.promote_replica.id
  policy = data.aws_iam_policy_document.promote_replica.json
}

resource "aws_lambda_function" "promote_replica" {
  provider = aws.us_east_1

  function_name = "multi-region-dr-promote-replica"
  role          = aws_iam_role.promote_replica.arn
  handler       = "promote_replica.handler"
  runtime       = "python3.12"
  timeout       = 30

  filename         = data.archive_file.promote_replica.output_path
  source_code_hash = data.archive_file.promote_replica.output_base64sha256

  environment {
    variables = {
      SECONDARY_REGION        = var.secondary_region
      SECONDARY_DB_IDENTIFIER = local.secondary_db_identifier
      PRIMARY_REGION          = var.primary_region
      PRIMARY_DB_IDENTIFIER   = local.primary_db_identifier
    }
  }

  dead_letter_config {
    target_arn = aws_sns_topic.promote_replica_dlq.arn
  }
}

# Deferred Medium item from Day 12 review: a failed or refused
# promotion (e.g. the Lambda errors before it can log its reason)
# should be visible, not silent.
resource "aws_sns_topic" "promote_replica_dlq" {
  provider = aws.us_east_1
  name     = "multi-region-dr-promote-replica-dlq"
}

resource "aws_sns_topic_subscription" "dlq_email" {
  count = var.alert_email != null ? 1 : 0

  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.promote_replica_dlq.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "promote_replica_errors" {
  provider = aws.us_east_1

  alarm_name          = "multi-region-dr-promote-replica-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.promote_replica.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.promote_replica_dlq.arn]

  alarm_description = "The replica-promotion Lambda errored — a failover may have silently failed to promote"
}

resource "aws_sns_topic_subscription" "lambda" {
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.failover.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.promote_replica.arn
}

resource "aws_lambda_permission" "sns_invoke" {
  provider      = aws.us_east_1
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.promote_replica.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.failover.arn
}

output "failover_sns_topic_arn" {
  value = aws_sns_topic.failover.arn
}

output "promote_replica_function_name" {
  value = aws_lambda_function.promote_replica.function_name
}
