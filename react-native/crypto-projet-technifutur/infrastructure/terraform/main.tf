terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "cryptoportfolio-tfstate"
    key            = "global/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "CryptoPortfolio"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

module "vpc" {
  source = "./modules/vpc"

  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  aws_region           = var.aws_region
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
}

module "security" {
  source = "./modules/security"

  environment = var.environment
  vpc_id      = module.vpc.vpc_id
}

module "rds" {
  source = "./modules/rds"

  environment         = var.environment
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  security_group_ids  = [module.security.rds_sg_id]
  allowed_cidr_blocks = [var.vpc_cidr]
}

module "ecs" {
  source = "./modules/ecs"

  environment         = var.environment
  aws_region          = var.aws_region
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  security_group_ids  = [module.security.ecs_sg_id]
  ecr_repository_url  = var.ecr_repository_url
  image_tag           = var.image_tag
  frontend_image_tag  = var.frontend_image_tag
  database_secret_arn = module.rds.db_secret_arn
}
