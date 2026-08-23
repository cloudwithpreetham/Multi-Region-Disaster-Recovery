# Three-tier chain: internet -> ALB -> app -> RDS.
# Each tier only accepts traffic from the tier in front of it, not from the
# internet or from each other directly.

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${local.role}-alb-sg"
  description = "Allow inbound HTTP/HTTPS from the internet to the ALB"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${local.role}-alb-sg"
  })
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-${local.role}-app-sg"
  description = "Allow inbound app traffic from the ALB only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "App port from ALB"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${local.role}-app-sg"
  })
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${local.role}-rds-sg"
  description = "Allow inbound DB traffic from the app tier only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "DB port from app tier"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${local.role}-rds-sg"
  })
}
