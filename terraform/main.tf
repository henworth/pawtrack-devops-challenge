terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket = "pawtrack-terraform-state"
    key    = "production/terraform.tfstate"
    region = "us-east-1"

    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "pawtrack"
      Environment = var.environment
    }
  }
}
