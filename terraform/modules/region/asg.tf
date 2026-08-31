data "aws_ami" "app" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-${local.role}-app-"
  image_id      = data.aws_ami.app.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.app.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  # Minimal placeholder — brings up a health-check endpoint on app_port so
  # the ALB target group goes healthy. Real app deploy replaces this later.
  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum install -y python3
    mkdir -p /srv/app && cd /srv/app
    echo "ok" > health
    nohup python3 -m http.server ${var.app_port} --directory /srv/app &
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${var.project_name}-${local.role}-app"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "${var.project_name}-${local.role}-app-asg"
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 60

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # Pre-initialized stopped instances alongside the group — meaningful
  # specifically for a standby region: it normally sits at low
  # desired_capacity to save cost, but Day 10's promotion can happen
  # at any moment and needs to absorb traffic fast, not after a cold
  # multi-minute scale-out. `warm_pool` is a nested block on the ASG
  # itself in this provider, not a separate resource.
  dynamic "warm_pool" {
    for_each = var.enable_warm_pool ? [1] : []
    content {
      pool_state = "Stopped"
      min_size   = var.warm_pool_min_size
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${local.role}-app"
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = local.role
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Target-tracking scaling — desired_capacity is just the baseline;
# actual capacity flexes with load. Matters most for secondary: after
# a Day 10 promotion it suddenly carries production traffic instead of
# nothing, and a fixed desired_capacity wouldn't react to that on its own.
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${var.project_name}-${local.role}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.scale_target_cpu
  }
}
