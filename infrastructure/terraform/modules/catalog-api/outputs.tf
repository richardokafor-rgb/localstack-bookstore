output "api_endpoint" {
  value = aws_apigatewayv2_api.catalog.api_endpoint
}
output "api_id" {
  value = aws_apigatewayv2_api.catalog.id
}
output "lambda_function_name" {
  value = aws_lambda_function.books.function_name
}
output "lambda_function_arn" {
  value = aws_lambda_function.books.arn
}
