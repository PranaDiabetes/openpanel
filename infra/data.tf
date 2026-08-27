# ASSUMPTION TO VERIFY BEFORE FIRST APPLY (Task 18): these tag/name lookups
# assume the develop/production VPC, ALB, ECS cluster, and security groups
# already exist with the exact naming prana_console's infra uses for its own
# environments. Confirm in the AWS console (or `aws ec2 describe-vpcs
# --filters "Name=tag:Name,Values=develop-vpc"` etc.) before running
# `terraform apply` for real.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "selected" {
  tags = {
    Name = local.vpc_name
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }

  tags = {
    type = "private"
  }
}

data "aws_ecs_cluster" "selected" {
  cluster_name = local.cluster_name
}

data "aws_lb" "selected" {
  name = local.alb_name
}

data "aws_lb_listener" "https" {
  load_balancer_arn = data.aws_lb.selected.arn
  port              = 443
}

data "aws_route53_zone" "dot_com" {
  name         = "habitnu.com"
  private_zone = false
}

data "aws_service_discovery_dns_namespace" "selected" {
  name = local.service_discovery_namespace_name
  type = "DNS_PRIVATE"
}

data "aws_security_group" "web" {
  tags = {
    Name = "ecs-web-${var.env_name}"
  }
}

data "aws_security_group" "worker" {
  tags = {
    Name = "ecs-worker-${var.env_name}"
  }
}
