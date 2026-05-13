resource "aws_dynamodb_table" "books" {
  name         = "${var.environment}-books"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "bookId"

  attribute {
    name = "bookId"
    type = "S"
  }
  attribute {
    name = "genre"
    type = "S"
  }

  global_secondary_index {
    name            = "genre-index"
    hash_key        = "genre"
    projection_type = "ALL"
  }

  tags = {
    Name = "${var.environment}-books"
  }
}

resource "aws_dynamodb_table" "orders" {
  name         = "${var.environment}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "orderId"

  attribute {
    name = "orderId"
    type = "S"
  }
  attribute {
    name = "userId"
    type = "S"
  }

  global_secondary_index {
    name            = "userId-index"
    hash_key        = "userId"
    projection_type = "ALL"
  }

  tags = {
    Name = "${var.environment}-orders"
  }
}

resource "aws_dynamodb_table" "users" {
  name         = "${var.environment}-users"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  tags = {
    Name = "${var.environment}-users"
  }
}
