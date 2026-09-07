resource "aws_elasticache_subnet_group" "redis" {
  name       = "openpanel-${var.env_name}"
  subnet_ids = data.aws_subnets.private.ids
}

resource "aws_elasticache_parameter_group" "redis" {
  name   = "openpanel-${var.env_name}-redis7"
  family = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "noeviction"
  }
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "openpanel-${var.env_name}"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = local.is_production ? "cache.t4g.small" : "cache.t4g.micro"
  num_cache_nodes      = 1
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.redis.name

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]
}
