module "worker_task_definition" {
  source = "./modules/ecs-task-definition"

  env_name           = var.env_name
  role               = local.worker_role
  image              = "${aws_ecr_repository.repo["worker"].repository_url}:latest"
  cpu                = local.cpu_worker
  memory             = local.memory_worker
  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  environment = {
    NODE_ENV                  = "production"
    SELF_HOSTED               = "true"
    BATCH_SIZE                = "5000"
    BATCH_INTERVAL            = "10000"
    CONCURRENCY               = "10"
    REDIS_URL                 = "redis://${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379"
    CLICKHOUSE_URL            = "http://${local.clickhouse_internal_hostname}:8123/openpanel"
    NEXT_PUBLIC_DASHBOARD_URL = "https://${local.dashboard_hostname}"
    DISABLE_BULLBOARD         = "1"
  }

  secrets = {
    DATABASE_URL        = aws_secretsmanager_secret.database_url.arn
    DATABASE_URL_DIRECT = aws_secretsmanager_secret.database_url.arn
    ENCRYPTION_KEY      = aws_secretsmanager_secret.encryption_key.arn
    COOKIE_SECRET       = aws_secretsmanager_secret.cookie_secret.arn
  }
}

resource "aws_ecs_service" "worker" {
  name             = local.worker_service_name
  cluster          = data.aws_ecs_cluster.selected.arn
  task_definition  = module.worker_task_definition.task_definition_arn
  desired_count    = local.worker_desired_count
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = false
  }

  network_configuration {
    assign_public_ip = false
    security_groups  = [data.aws_security_group.worker.id]
    subnets          = data.aws_subnets.private.ids
  }

  lifecycle {
    create_before_destroy = true
  }
}
