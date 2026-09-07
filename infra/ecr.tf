locals {
  ecr_repo_names = {
    api        = "openpanel-${var.env_name}-api"
    worker     = "openpanel-${var.env_name}-worker"
    dashboard  = "openpanel-${var.env_name}-dashboard"
    clickhouse = "openpanel-${var.env_name}-clickhouse"
  }
}

resource "aws_ecr_repository" "repo" {
  for_each = local.ecr_repo_names

  name                 = each.value
  image_tag_mutability = "MUTABLE"
  force_delete         = !local.is_production

  image_scanning_configuration {
    scan_on_push = true
  }
}
