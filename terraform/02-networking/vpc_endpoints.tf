# VPC Endpoints for SSM services to enable SSM Agent functionality
# without requiring internet access through NAT Gateway

# SSM VPC Endpoint
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.envoy_poc_vpc.id
  service_name        = "com.amazonaws.${local.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.envoy_poc_private_subnets[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-ssm-endpoint"
  })
}

# SSM Messages VPC Endpoint
resource "aws_vpc_endpoint" "ssm_messages" {
  vpc_id              = aws_vpc.envoy_poc_vpc.id
  service_name        = "com.amazonaws.${local.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.envoy_poc_private_subnets[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-ssm-messages-endpoint"
  })
}

# EC2 Messages VPC Endpoint
resource "aws_vpc_endpoint" "ec2_messages" {
  vpc_id              = aws_vpc.envoy_poc_vpc.id
  service_name        = "com.amazonaws.${local.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.envoy_poc_private_subnets[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-ec2-messages-endpoint"
  })
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.project_name}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.envoy_poc_vpc.id

  # Allow HTTPS traffic from private subnets
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.private_subnet_cidrs
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-vpc-endpoints-sg"
  })
}
