variable "environment" {
  type = string
}
variable "orders_table" {
  type = string
}
variable "orders_table_arn" {
  type = string
}
variable "users_table" {
  type = string
}
variable "users_table_arn" {
  type = string
}
variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "container_image" {
  type        = string
  description = "Full ECR image URI for the order-service container"
  default     = ""
}
