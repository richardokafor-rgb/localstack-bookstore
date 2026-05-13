output "books_table_name" {
  value = aws_dynamodb_table.books.name
}
output "books_table_arn" {
  value = aws_dynamodb_table.books.arn
}
output "orders_table_name" {
  value = aws_dynamodb_table.orders.name
}
output "orders_table_arn" {
  value = aws_dynamodb_table.orders.arn
}
output "users_table_name" {
  value = aws_dynamodb_table.users.name
}
output "users_table_arn" {
  value = aws_dynamodb_table.users.arn
}
