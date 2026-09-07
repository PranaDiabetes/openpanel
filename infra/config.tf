terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  required_version = ">= 1.2.0"

  # bucket/key/region are supplied at `terraform init -backend-config=...`
  # time (see infra/README.md, Task 18) — never hardcode real values here.
  backend "s3" {
    bucket = "placeholder"
    key    = "placeholder"
    region = "us-east-1"
  }
}

provider "aws" {
  default_tags {
    tags = {
      environment = var.env_name
      application = local.application_name
      managed_by  = "openpanel/infra"
    }
  }
}
