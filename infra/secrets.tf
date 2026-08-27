resource "random_id" "encryption_key" {
  byte_length = 32
}

resource "aws_secretsmanager_secret" "encryption_key" {
  name                    = "openpanel-${var.env_name}-encryption-key"
  recovery_window_in_days = local.is_production ? 30 : 0
}

resource "aws_secretsmanager_secret_version" "encryption_key" {
  secret_id     = aws_secretsmanager_secret.encryption_key.id
  secret_string = random_id.encryption_key.hex
}

resource "random_password" "cookie_secret" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "cookie_secret" {
  name                    = "openpanel-${var.env_name}-cookie-secret"
  recovery_window_in_days = local.is_production ? 30 : 0
}

resource "aws_secretsmanager_secret_version" "cookie_secret" {
  secret_id     = aws_secretsmanager_secret.cookie_secret.id
  secret_string = random_password.cookie_secret.result
}
