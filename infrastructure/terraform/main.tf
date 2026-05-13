terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "aws" {
  region                      = var.aws_region
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = false

  default_tags {
    tags = {
      Project     = "localstack-bookstore"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

module "dynamodb" {
  source      = "./modules/dynamodb"
  environment = var.environment
}

module "frontend" {
  source      = "./modules/frontend"
  environment = var.environment
}

module "catalog_api" {
  source          = "./modules/catalog-api"
  environment     = var.environment
  books_table     = module.dynamodb.books_table_name
  books_table_arn = module.dynamodb.books_table_arn
}

module "order_service" {
  source           = "./modules/order-service"
  environment      = var.environment
  aws_region       = var.aws_region
  orders_table     = module.dynamodb.orders_table_name
  orders_table_arn = module.dynamodb.orders_table_arn
  users_table      = module.dynamodb.users_table_name
  users_table_arn  = module.dynamodb.users_table_arn
  container_image  = var.order_service_image
}
