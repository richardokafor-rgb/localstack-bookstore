locals {
  service_dir  = "${path.root}/../../services/catalog-api"
  lambda_zip   = "${path.module}/catalog-api.zip"
}

resource "null_resource" "catalog_api_build" {
  triggers = {
    package_json = filesha256("${local.service_dir}/package.json")
    handler      = filesha256("${local.service_dir}/src/handlers/books.js")
  }
  provisioner "local-exec" {
    working_dir = local.service_dir
    command     = "npm install --production --silent"
  }
}

data "archive_file" "catalog_api" {
  depends_on  = [null_resource.catalog_api_build]
  type        = "zip"
  source_dir  = local.service_dir
  output_path = local.lambda_zip
  excludes    = ["*.test.js", "jest.config.*", ".npmrc"]
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.environment}-catalog-api-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "${var.environment}-catalog-api-dynamodb"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query",
        ]
        Resource = [var.books_table_arn, "${var.books_table_arn}/index/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}

resource "aws_lambda_function" "books" {
  filename         = data.archive_file.catalog_api.output_path
  source_code_hash = data.archive_file.catalog_api.output_base64sha256
  function_name    = "${var.environment}-books-handler"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "src/handlers/books.handler"
  runtime          = "nodejs18.x"
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      BOOKS_TABLE = var.books_table
    }
  }
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.books.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.catalog.execution_arn}/*/*"
}

resource "aws_apigatewayv2_api" "catalog" {
  name          = "${var.environment}-bookstore-catalog"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 3600
  }
}

resource "aws_apigatewayv2_integration" "books" {
  api_id                 = aws_apigatewayv2_api.catalog.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.books.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "list_books" {
  api_id    = aws_apigatewayv2_api.catalog.id
  route_key = "GET /books"
  target    = "integrations/${aws_apigatewayv2_integration.books.id}"
}

resource "aws_apigatewayv2_route" "create_book" {
  api_id    = aws_apigatewayv2_api.catalog.id
  route_key = "POST /books"
  target    = "integrations/${aws_apigatewayv2_integration.books.id}"
}

resource "aws_apigatewayv2_route" "get_book" {
  api_id    = aws_apigatewayv2_api.catalog.id
  route_key = "GET /books/{bookId}"
  target    = "integrations/${aws_apigatewayv2_integration.books.id}"
}

resource "aws_apigatewayv2_route" "update_book" {
  api_id    = aws_apigatewayv2_api.catalog.id
  route_key = "PUT /books/{bookId}"
  target    = "integrations/${aws_apigatewayv2_integration.books.id}"
}

resource "aws_apigatewayv2_route" "delete_book" {
  api_id    = aws_apigatewayv2_api.catalog.id
  route_key = "DELETE /books/{bookId}"
  target    = "integrations/${aws_apigatewayv2_integration.books.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.catalog.id
  name        = "$default"
  auto_deploy = true
}
