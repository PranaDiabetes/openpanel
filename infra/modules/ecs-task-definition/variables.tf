variable "env_name" {
  type = string
}

variable "role" {
  description = "Service role name, e.g. \"api\", \"worker\", \"dashboard\""
  type        = string
}

variable "image" {
  description = "Full image URI including tag, e.g. \"<ecr-repo-url>:latest\""
  type        = string
}

variable "container_port" {
  type    = number
  default = 3000
}

variable "cpu" {
  type = number
}

variable "memory" {
  type = number
}

variable "execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "environment" {
  description = "Plain (non-secret) environment variables"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Env var name => Secrets Manager secret ARN"
  type        = map(string)
  default     = {}
}

variable "command" {
  description = "Container command override; null uses the image's default CMD"
  type        = list(string)
  default     = null
}
