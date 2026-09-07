module "dashboard_task_definition" {
  source = "./modules/ecs-task-definition"

  env_name           = var.env_name
  role               = local.dashboard_role
  image              = "${aws_ecr_repository.repo["dashboard"].repository_url}:latest"
  cpu                = local.cpu_dashboard
  memory             = local.memory_dashboard
  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  environment = {
    NODE_ENV                  = "production"
    SELF_HOSTED               = "true"
    ALLOW_REGISTRATION        = "true"
    REDIS_URL                 = "redis://${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379"
    CLICKHOUSE_URL            = "http://${local.clickhouse_internal_hostname}:8123/openpanel"
    NEXT_PUBLIC_API_URL       = "https://${local.api_hostname}"
    NEXT_PUBLIC_DASHBOARD_URL = "https://${local.dashboard_hostname}"
  }

  secrets = {
    DATABASE_URL        = aws_secretsmanager_secret.database_url.arn
    DATABASE_URL_DIRECT = aws_secretsmanager_secret.database_url.arn
    ENCRYPTION_KEY      = aws_secretsmanager_secret.encryption_key.arn
    COOKIE_SECRET       = aws_secretsmanager_secret.cookie_secret.arn
  }
}

resource "aws_lb_target_group" "dashboard" {
  name        = "openpanel-${var.env_name}-dashboard"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.selected.id

  health_check {
    enabled             = true
    path                = "/api/healthcheck"
    port                = "traffic-port"
    protocol            = "HTTP"
    interval            = 30
    unhealthy_threshold = 10
  }
}

resource "aws_lb_listener_rule" "dashboard" {
  listener_arn = data.aws_lb_listener.https.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dashboard.arn
  }

  condition {
    host_header {
      values = [local.dashboard_hostname]
    }
  }
}

resource "aws_route53_record" "dashboard" {
  zone_id = data.aws_route53_zone.dot_com.zone_id
  name    = local.dashboard_hostname
  type    = "CNAME"
  ttl     = 300
  records = [data.aws_lb.selected.dns_name]
}

resource "aws_ecs_service" "dashboard" {
  name                              = local.dashboard_service_name
  cluster                           = data.aws_ecs_cluster.selected.arn
  task_definition                   = module.dashboard_task_definition.task_definition_arn
  desired_count                     = 1
  launch_type                       = "FARGATE"
  platform_version                  = "LATEST"
  health_check_grace_period_seconds = 300

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = false
  }

  network_configuration {
    assign_public_ip = false
    security_groups  = [data.aws_security_group.web.id]
    subnets          = data.aws_subnets.private.ids
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.dashboard.arn
    container_name   = module.dashboard_task_definition.container_name
    container_port   = 3000
  }

  lifecycle {
    create_before_destroy = true
  }
}
