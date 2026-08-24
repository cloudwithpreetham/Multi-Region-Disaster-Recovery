resource "aws_lb" "this" {
  name               = "${var.project_name}-${local.role}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # Portfolio project — no deletion protection so `terraform destroy`
  # between sessions (see AGENT.md cost notes) isn't blocked.
  enable_deletion_protection = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${local.role}-alb"
  })
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-${local.role}-app-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "instance"

  health_check {
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${local.role}-app-tg"
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  # HTTPS/ACM listener deferred — no domain/cert wired up yet.
  # CloudFront (Phase 4) will front this over HTTPS regardless.
}
