resource "aws_cloudwatch_log_group" "clickhouse" {
  name              = "/ecs/openpanel-${var.env_name}-clickhouse"
  retention_in_days = 30
}

resource "aws_ecs_task_definition" "clickhouse" {
  family                   = local.clickhouse_service_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = local.cpu_clickhouse
  memory                   = local.memory_clickhouse
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  volume {
    name = "clickhouse-data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.clickhouse.id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.clickhouse.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "clickhouse"
      image     = "${aws_ecr_repository.repo["clickhouse"].repository_url}:latest"
      essential = true

      portMappings = [
        { containerPort = 8123, protocol = "tcp" },
        { containerPort = 9000, protocol = "tcp" }
      ]

      mountPoints = [
        {
          sourceVolume  = "clickhouse-data"
          containerPath = "/var/lib/clickhouse"
          readOnly      = false
        }
      ]

      environment = [
        { name = "CLICKHOUSE_DB", value = "openpanel" },
        { name = "CLICKHOUSE_SKIP_USER_SETUP", value = "1" }
      ]

      ulimits = [
        { name = "nofile", softLimit = 262144, hardLimit = 262144 }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.clickhouse.name
          awslogs-region        = data.aws_region.current.id
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_service_discovery_service" "clickhouse" {
  name = "clickhouse"

  dns_config {
    namespace_id = data.aws_service_discovery_dns_namespace.selected.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }
}

resource "aws_ecs_service" "clickhouse" {
  name             = local.clickhouse_service_name
  cluster          = data.aws_ecs_cluster.selected.arn
  task_definition  = aws_ecs_task_definition.clickhouse.arn
  desired_count    = 1
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  # The old task must fully stop before the new one starts: two ClickHouse
  # processes must never write the same EFS-backed data directory at once.
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  network_configuration {
    assign_public_ip = false
    security_groups  = [aws_security_group.clickhouse.id]
    subnets          = data.aws_subnets.private.ids
  }

  service_registries {
    registry_arn = aws_service_discovery_service.clickhouse.arn
  }

  depends_on = [aws_efs_mount_target.clickhouse]
}

data "aws_iam_policy_document" "clickhouse_efs_access" {
  statement {
    actions   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
    effect    = "Allow"
    resources = [aws_efs_file_system.clickhouse.arn]

    condition {
      test     = "StringEquals"
      variable = "elasticfilesystem:AccessPointArn"
      values   = [aws_efs_access_point.clickhouse.arn]
    }
  }
}

resource "aws_iam_role_policy" "clickhouse_efs_access" {
  name   = "clickhouse-efs-access-${var.env_name}"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.clickhouse_efs_access.json
}
