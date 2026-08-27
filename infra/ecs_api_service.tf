module "api_task_definition" {
  source = "./modules/ecs-task-definition"

  env_name           = var.env_name
  role               = local.api_role
  image              = "${aws_ecr_repository.repo["api"].repository_url}:latest"
  cpu                = local.cpu_api
  memory             = local.memory_api
  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  # Matches the official self-hosting docker-compose: run migrations, then
  # start the server.
  command = ["sh", "-c", "CI=true pnpm -r run migrate:deploy && pnpm start"]

  environment = {
    NODE_ENV                  = "production"
    API_HOST                  = "0.0.0.0"
    ALLOW_REGISTRATION        = "true"
    SELF_HOSTED               = "true"
    BATCH_SIZE                = "5000"
    BATCH_INTERVAL            = "10000"
    CONCURRENCY               = "10"
    REDIS_URL                 = "redis://${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379"
    CLICKHOUSE_URL            = "http://${local.clickhouse_internal_hostname}:8123/openpanel"
    NEXT_PUBLIC_API_URL       = "https://${local.api_hostname}"
    NEXT_PUBLIC_DASHBOARD_URL = "https://${local.dashboard_hostname}"
    API_CORS_ORIGINS          = "https://${local.dashboard_hostname}"
  }

  secrets = {
    DATABASE_URL        = aws_secretsmanager_secret.database_url.arn
    DATABASE_URL_DIRECT = aws_secretsmanager_secret.database_url.arn
    ENCRYPTION_KEY      = aws_secretsmanager_secret.encryption_key.arn
    COOKIE_SECRET       = aws_secretsmanager_secret.cookie_secret.arn
  }
}

resource "aws_lb_target_group" "api" {
  name        = "openpanel-${var.env_name}-api"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.selected.id

  health_check {
    enabled             = true
    path                = "/healthz/ready"
    port                = "traffic-port"
    protocol            = "HTTP"
    interval            = 30
    unhealthy_threshold = 10
  }
}

resource "aws_lb_listener_rule" "api" {
  listener_arn = data.aws_lb_listener.https.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  condition {
    host_header {
      values = [local.api_hostname]
    }
  }
}

resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.dot_com.zone_id
  name    = local.api_hostname
  type    = "CNAME"
  ttl     = 300
  records = [data.aws_lb.selected.dns_name]
}

resource "aws_ecs_service" "api" {
  name                              = local.api_service_name
  cluster                           = data.aws_ecs_cluster.selected.arn
  task_definition                   = module.api_task_definition.task_definition_arn
  desired_count                     = 1
  launch_type                       = "FARGATE"
  platform_version                  = "LATEST"
  health_check_grace_period_seconds = 600

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
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = module.api_task_definition.container_name
    container_port   = 3000
  }

  lifecycle {
    create_before_destroy = true
  }
}
