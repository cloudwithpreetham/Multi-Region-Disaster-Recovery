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

resource "aws_acm_certificate" "alb" {
  count = var.origin_domain_name != null && var.dns_zone_id != null ? 1 : 0

  domain_name       = var.origin_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "alb_cert_validation" {
  for_each = var.origin_domain_name != null && var.dns_zone_id != null ? {
    for dvo in aws_acm_certificate.alb[0].domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  } : {}

  zone_id = var.dns_zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "alb" {
  count = var.origin_domain_name != null && var.dns_zone_id != null ? 1 : 0

  certificate_arn         = aws_acm_certificate.alb[0].arn
  validation_record_fqdns = [for record in aws_route53_record.alb_cert_validation : record.fqdn]
}

resource "aws_route53_record" "alb_origin" {
  count = var.origin_domain_name != null && var.dns_zone_id != null ? 1 : 0

  zone_id = var.dns_zone_id
  name    = var.origin_domain_name
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

resource "aws_lb_listener" "https" {
  count = var.origin_domain_name != null && var.dns_zone_id != null ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.alb[0].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
