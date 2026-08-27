output "ecr_repository_urls" {
  description = "ECR repository URL for each service, keyed by role"
  value       = { for role, repo in aws_ecr_repository.repo : role => repo.repository_url }
}

output "dashboard_url" {
  value = "https://${local.dashboard_hostname}"
}

output "api_url" {
  value = "https://${local.api_hostname}"
}

output "ecs_cluster_name" {
  value = data.aws_ecs_cluster.selected.cluster_name
}
