output "order_queue_url" {
  value = aws_sqs_queue.orders.url
}
output "order_queue_arn" {
  value = aws_sqs_queue.orders.arn
}
output "order_dlq_url" {
  value = aws_sqs_queue.orders_dlq.url
}
output "notifications_topic_arn" {
  value = aws_sns_topic.order_notifications.arn
}
output "ecr_repository_url" {
  value = aws_ecr_repository.order_service.repository_url
}
output "ecs_cluster_name" {
  value = aws_ecs_cluster.bookstore.name
}
output "ecs_service_name" {
  value = aws_ecs_service.order_service.name
}
