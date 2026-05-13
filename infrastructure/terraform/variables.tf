variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "local"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "order_service_image" {
  type        = string
  description = "ECR image URI for the order-service container (overrides default)"
  default     = ""
}
