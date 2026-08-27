data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "ecs-execution-openpanel-${var.env_name}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS injects `secrets` (Secrets Manager -> env var) using the *execution*
# role, not the task role — this policy is what makes DATABASE_URL,
# DATABASE_URL_DIRECT, ENCRYPTION_KEY, and COOKIE_SECRET resolvable at
# container start.
data "aws_iam_policy_document" "read_secrets" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    effect  = "Allow"
    resources = [
      aws_secretsmanager_secret.encryption_key.arn,
      aws_secretsmanager_secret.database_url.arn,
      aws_secretsmanager_secret.cookie_secret.arn,
    ]
  }
}

resource "aws_iam_role_policy" "ecs_execution_read_secrets" {
  name   = "read-secrets-openpanel-${var.env_name}"
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.read_secrets.json
}

# No additional policies attached yet — openpanel's app code doesn't call
# any AWS APIs at runtime beyond what the execution role already covers.
# Add statements here if that changes (e.g. S3 export/import support).
resource "aws_iam_role" "ecs_task" {
  name               = "ecs-task-openpanel-${var.env_name}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}
