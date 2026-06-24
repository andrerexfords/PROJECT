terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # State disimpan di S3 (shared, encrypted, versioned).
  # NOTE: backend config TIDAK bisa pakai variable — hardcoded.
  # Bucket harus EXIST + AWS creds harus punya s3:GetObject/PutObject access.
  backend "s3" {
    bucket  = "prj-idvend"
    key     = "prj-aws-glchat/standalone/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
    # Untuk multi-environment, override key via:
    #   terraform init -backend-config="key=prj-aws-glchat/<env>/terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}
