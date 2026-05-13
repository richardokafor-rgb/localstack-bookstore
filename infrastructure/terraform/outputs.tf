output "api_endpoint" {
  description = "Catalog API Gateway endpoint"
  value       = module.catalog_api.api_endpoint
}

output "frontend_bucket" {
  description = "S3 bucket for the React frontend"
  value       = module.frontend.bucket_name
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain"
  value       = module.frontend.cloudfront_domain_name
}

output "order_queue_url" {
  description = "SQS order queue URL"
  value       = module.order_service.order_queue_url
}

output "notifications_topic_arn" {
  description = "SNS order notifications topic ARN"
  value       = module.order_service.notifications_topic_arn
}

output "ecr_repository_url" {
  description = "ECR repository URL for the order service"
  value       = module.order_service.ecr_repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.order_service.ecs_cluster_name
}

output "books_table" {
  value = module.dynamodb.books_table_name
}

output "orders_table" {
  value = module.dynamodb.orders_table_name
}
