resource "aws_s3_bucket" "frontend" {
  bucket = "${var.environment}-bookstore-frontend"
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }
  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "frontend" {
  depends_on = [aws_s3_bucket_public_access_block.frontend]
  bucket     = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
    }]
  })
}

locals {
  frontend_dir = "${path.root}/../../frontend"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    domain_name = aws_s3_bucket_website_configuration.frontend.website_endpoint
    origin_id   = "S3-${aws_s3_bucket.frontend.id}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "S3-${aws_s3_bucket.frontend.id}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${var.environment}-bookstore-cdn"
  }
}

# Build the React app and upload dist/ to S3 whenever the API endpoint or
# source files change.
resource "null_resource" "frontend_deploy" {
  depends_on = [
    aws_s3_bucket_policy.frontend,
    aws_cloudfront_distribution.frontend,
  ]

  triggers = {
    api_endpoint = var.api_endpoint
    src_hash = sha256(join("", [
      filesha256("${local.frontend_dir}/src/App.jsx"),
      filesha256("${local.frontend_dir}/src/api/client.js"),
      filesha256("${local.frontend_dir}/package.json"),
    ]))
  }

  provisioner "local-exec" {
    working_dir = local.frontend_dir
    environment = {
      VITE_API_ENDPOINT      = var.api_endpoint
      VITE_ORDER_SERVICE_URL = "http://localhost:5001"
    }
    command = <<-EOT
      set -e
      npm install --silent
      npm run build
      awslocal s3 sync dist/ s3://${aws_s3_bucket.frontend.id}/ --delete
      awslocal s3 cp dist/index.html s3://${aws_s3_bucket.frontend.id}/index.html \
        --content-type text/html --cache-control "no-cache, no-store"
    EOT
  }
}
