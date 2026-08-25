data "aws_iam_policy_document" "app_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.project_name}-${local.role}-app-role"
  assume_role_policy = data.aws_iam_policy_document.app_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${local.role}-app-role"
  })
}

# SSM Session Manager access — no SSH/bastion needed to reach instances
# in the private subnets, useful for the failover drill (Day 7+) when
# checking instance state during a simulated outage.
resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch agent — metrics/logs for health-check debugging and
# eventually the failover runbook's "how do we know it's down" signal.
resource "aws_iam_role_policy_attachment" "app_cloudwatch" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-${local.role}-app-profile"
  role = aws_iam_role.app.name
}
