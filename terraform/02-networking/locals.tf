locals {
  # Project Configuration
  project_name = "envoy-poc"
  environment  = "dev"
  
  # VPC Configuration
  vpc_name = "envoy-vpc"
  vpc_cidr = "172.245.0.0/16"
  
  # Availability Zones
  availability_zones = ["us-west-2a", "us-west-2b"]
  
  # Subnet Configuration
  public_subnet_cidrs  = ["172.245.1.0/24", "172.245.2.0/24"]
  private_subnet_cidrs = ["172.245.10.0/24", "172.245.20.0/24"]
  
  # AWS Region
  aws_region = "us-west-2"
  
  # AWS Profile
  aws_profile = "avive-cfndev-k8s"
  
  # Common Tags
  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
    Purpose     = "envoy-proxy-poc"
  }
}
