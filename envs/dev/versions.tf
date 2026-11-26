terraform {
  required_version = ">= 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-west-3"

  default_tags {
    tags = {
      Project     = "novasphere"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
