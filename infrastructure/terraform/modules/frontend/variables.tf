variable "environment" {
  type = string
}

variable "api_endpoint" {
  type        = string
  description = "Catalog API Gateway endpoint injected into the React build as VITE_API_ENDPOINT"
}
