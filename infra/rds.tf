resource "aws_db_subnet_group" "postgres" {
  name       = "openpanel-${var.env_name}"
  subnet_ids = data.aws_subnets.private.ids
}

# Generated (not RDS-managed) so Terraform can compose the single
# DATABASE_URL connection string the app expects. State should be treated
# as sensitive — this is the same trust boundary the org's S3-env-file
# pattern already relies on.
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_db_instance" "postgres" {
  identifier     = "openpanel-${var.env_name}"
  engine         = "postgres"
  engine_version = "16"
  instance_class = local.is_production ? "db.t4g.small" : "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "openpanel"
  username = "openpanel"
  password = random_password.db.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  backup_retention_period = local.is_production ? 7 : 1
  deletion_protection     = local.is_production
  skip_final_snapshot     = !local.is_production
  # Static identifier is fine for a single planned deletion; rename this
  # (or add a timestamp) if you ever need to destroy and recreate the
  # production instance more than once.
  final_snapshot_identifier = local.is_production ? "openpanel-${var.env_name}-final" : null

  apply_immediately = !local.is_production
}

resource "aws_secretsmanager_secret" "database_url" {
  name                    = "openpanel-${var.env_name}-database-url"
  recovery_window_in_days = local.is_production ? 30 : 0
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = "postgresql://${aws_db_instance.postgres.username}:${random_password.db.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/${aws_db_instance.postgres.db_name}?schema=public"
}
