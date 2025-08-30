# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.envoy_poc_vpc.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.envoy_poc_vpc.cidr_block
}

# Subnet Outputs
output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.envoy_poc_public_subnets[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.envoy_poc_private_subnets[*].id
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets"
  value       = aws_subnet.envoy_poc_public_subnets[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets"
  value       = aws_subnet.envoy_poc_private_subnets[*].cidr_block
}

# Internet Gateway Outputs
output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.envoy_poc_igw.id
}

# NAT Gateway Outputs
output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways"
  value       = aws_nat_gateway.envoy_poc_nat_gateways[*].id
}

output "nat_gateway_public_ips" {
  description = "Public IPs of the NAT Gateways"
  value       = aws_eip.envoy_poc_nat_eips[*].public_ip
}

# Route Table Outputs
output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.envoy_poc_public_rt.id
}

output "private_route_table_ids" {
  description = "IDs of the private route tables"
  value       = aws_route_table.envoy_poc_private_rts[*].id
}

# Security Group Outputs
output "eks_cluster_security_group_id" {
  description = "ID of the EKS cluster security group"
  value       = aws_security_group.envoy_poc_eks_cluster_sg.id
}

output "worker_node_security_group_id" {
  description = "ID of the worker node security group"
  value       = aws_security_group.envoy_poc_worker_node_sg.id
}

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.envoy_poc_alb_sg.id
}

output "envoy_service_security_group_id" {
  description = "ID of the Envoy service security group"
  value       = aws_security_group.envoy_poc_envoy_service_sg.id
}

# Availability Zones Output
output "availability_zones" {
  description = "Availability zones used for the subnets"
  value       = local.availability_zones
}

# VPC Endpoints Outputs
output "ssm_vpc_endpoint_id" {
  description = "ID of the SSM VPC endpoint"
  value       = aws_vpc_endpoint.ssm.id
}

output "ssm_messages_vpc_endpoint_id" {
  description = "ID of the SSM Messages VPC endpoint"
  value       = aws_vpc_endpoint.ssm_messages.id
}

output "ec2_messages_vpc_endpoint_id" {
  description = "ID of the EC2 Messages VPC endpoint"
  value       = aws_vpc_endpoint.ec2_messages.id
}

output "vpc_endpoints_security_group_id" {
  description = "ID of the VPC endpoints security group"
  value       = aws_security_group.vpc_endpoints.id
}
