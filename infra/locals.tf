locals {
  application_name = "openpanel"
  is_production    = var.env_name == "production"

  vpc_name                         = "${var.env_name}-vpc"
  cluster_name                     = local.is_production ? "habitnu" : "habitnu-${var.env_name}"
  alb_name                         = local.is_production ? "habitnu" : "habitnu-${var.env_name}"
  service_discovery_namespace_name = local.is_production ? "habitnu.local" : "habitnu-${var.env_name}.local"

  subdomain_suffix             = local.is_production ? "" : "-${var.env_name}"
  dashboard_hostname           = "analytics${local.subdomain_suffix}.habitnu.com"
  api_hostname                 = "analytics-api${local.subdomain_suffix}.habitnu.com"
  clickhouse_internal_hostname = "clickhouse.${local.service_discovery_namespace_name}"

  cpu_api           = local.is_production ? 512 : 256
  memory_api        = local.is_production ? 1024 : 512
  cpu_worker        = local.is_production ? 512 : 256
  memory_worker     = local.is_production ? 1024 : 512
  cpu_dashboard     = local.is_production ? 512 : 256
  memory_dashboard  = local.is_production ? 1024 : 512
  cpu_clickhouse    = local.is_production ? 1024 : 512
  memory_clickhouse = local.is_production ? 2048 : 1024

  worker_desired_count = local.is_production ? 2 : 1

  api_role        = "api"
  worker_role     = "worker"
  dashboard_role  = "dashboard"
  clickhouse_role = "clickhouse"

  api_service_name        = "openpanel-${var.env_name}-${local.api_role}"
  worker_service_name     = "openpanel-${var.env_name}-${local.worker_role}"
  dashboard_service_name  = "openpanel-${var.env_name}-${local.dashboard_role}"
  clickhouse_service_name = "openpanel-${var.env_name}-${local.clickhouse_role}"
}
