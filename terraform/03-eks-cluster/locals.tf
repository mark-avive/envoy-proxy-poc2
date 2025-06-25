locals {
  # Project Configuration
  project_name = "envoy-poc"
  environment  = "dev"
  
  # EKS Configuration
  cluster_name    = "envoy-poc"
  cluster_version = "1.33"  # Using latest stable version from requirements
  
  # Node Group Configuration
  node_group_name         = "${local.project_name}-worker-nodes"
  node_instance_type      = "t3.medium"
  node_desired_capacity   = 2
  node_min_capacity       = 2
  node_max_capacity       = 4
  node_ami_type          = "AL2023_x86_64_STANDARD"  # Amazon Linux 2023 for Kubernetes 1.33+
  
  # AWS Region and Profile
  aws_region  = "us-west-2"
  aws_profile = "avive-cfndev-k8s"
  
  # CloudWatch Log Groups
  cluster_log_types = ["api", "audit", "authenticator", "scheduler"]
  
  # Common Tags
  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
    Purpose     = "envoy-proxy-poc"
    Section     = "03-eks-cluster"
  }
}
