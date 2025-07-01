# Variables for Enhanced Envoy Deployment
# These variables can be overridden via terraform.tfvars or environment variables

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "envoy-poc"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "envoy_replicas" {
  description = "Number of Envoy proxy replicas"
  type        = number
  default     = 2
}

variable "custom_envoy_image" {
  description = "Custom Envoy image URI (if empty, will use default ECR image)"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "avive-cfndev-k8s"
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "default"
}

variable "max_connections_per_pod" {
  description = "Maximum WebSocket connections per backend pod"
  type        = number
  default     = 2
}

variable "rate_limit_requests_per_minute" {
  description = "Rate limit for new connections per minute"
  type        = number
  default     = 60
}

variable "redis_service_name" {
  description = "Name of the Redis service"
  type        = string
  default     = "redis-service"
}

variable "redis_port" {
  description = "Redis service port"
  type        = number
  default     = 6379
}
