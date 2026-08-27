variable "env_name" {
  description = "Environment name: production or develop"
  type        = string

  validation {
    condition     = contains(["production", "develop"], var.env_name)
    error_message = "env_name must be \"production\" or \"develop\"."
  }
}
