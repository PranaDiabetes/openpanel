resource "aws_security_group" "clickhouse" {
  name        = "openpanel-${var.env_name}-clickhouse"
  description = "ClickHouse ECS task for openpanel (${var.env_name})"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    description     = "ClickHouse HTTP interface from api/worker"
    from_port       = 8123
    to_port         = 8123
    protocol        = "tcp"
    security_groups = [data.aws_security_group.web.id, data.aws_security_group.worker.id]
  }

  ingress {
    description     = "ClickHouse native TCP interface from api/worker"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [data.aws_security_group.web.id, data.aws_security_group.worker.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name        = "openpanel-${var.env_name}-rds"
  description = "Postgres RDS instance for openpanel (${var.env_name})"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    description     = "Postgres from api/worker"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [data.aws_security_group.web.id, data.aws_security_group.worker.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "redis" {
  name        = "openpanel-${var.env_name}-redis"
  description = "ElastiCache Redis for openpanel (${var.env_name})"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    description     = "Redis from api/worker"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [data.aws_security_group.web.id, data.aws_security_group.worker.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "efs" {
  name        = "openpanel-${var.env_name}-efs"
  description = "EFS mount targets for openpanel ClickHouse storage (${var.env_name})"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    description     = "NFS from the ClickHouse task"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.clickhouse.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
