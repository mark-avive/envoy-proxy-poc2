# Data source to get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
resource "aws_vpc" "envoy_poc_vpc" {
  cidr_block           = local.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(local.common_tags, {
    Name = local.vpc_name
  })
}

# Internet Gateway
resource "aws_internet_gateway" "envoy_poc_igw" {
  vpc_id = aws_vpc.envoy_poc_vpc.id
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-igw"
  })
}

# Public Subnets
resource "aws_subnet" "envoy_poc_public_subnets" {
  count = length(local.public_subnet_cidrs)
  
  vpc_id                  = aws_vpc.envoy_poc_vpc.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = true
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-public-subnet-${count.index + 1}"
    Type = "Public"
    "kubernetes.io/role/elb" = "1"
  })
}

# Private Subnets
resource "aws_subnet" "envoy_poc_private_subnets" {
  count = length(local.private_subnet_cidrs)
  
  vpc_id            = aws_vpc.envoy_poc_vpc.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.availability_zones[count.index]
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-private-subnet-${count.index + 1}"
    Type = "Private"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "envoy_poc_nat_eips" {
  count = length(local.public_subnet_cidrs)
  
  domain = "vpc"
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-nat-eip-${count.index + 1}"
  })
  
  depends_on = [aws_internet_gateway.envoy_poc_igw]
}

# NAT Gateways
resource "aws_nat_gateway" "envoy_poc_nat_gateways" {
  count = length(local.public_subnet_cidrs)
  
  allocation_id = aws_eip.envoy_poc_nat_eips[count.index].id
  subnet_id     = aws_subnet.envoy_poc_public_subnets[count.index].id
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-nat-gateway-${count.index + 1}"
  })
  
  depends_on = [aws_internet_gateway.envoy_poc_igw]
}

# Public Route Table
resource "aws_route_table" "envoy_poc_public_rt" {
  vpc_id = aws_vpc.envoy_poc_vpc.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.envoy_poc_igw.id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-public-rt"
    Type = "Public"
  })
}

# Private Route Tables
resource "aws_route_table" "envoy_poc_private_rts" {
  count = length(local.private_subnet_cidrs)
  
  vpc_id = aws_vpc.envoy_poc_vpc.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.envoy_poc_nat_gateways[count.index].id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-private-rt-${count.index + 1}"
    Type = "Private"
  })
}

# Public Route Table Associations
resource "aws_route_table_association" "envoy_poc_public_rta" {
  count = length(aws_subnet.envoy_poc_public_subnets)
  
  subnet_id      = aws_subnet.envoy_poc_public_subnets[count.index].id
  route_table_id = aws_route_table.envoy_poc_public_rt.id
}

# Private Route Table Associations
resource "aws_route_table_association" "envoy_poc_private_rta" {
  count = length(aws_subnet.envoy_poc_private_subnets)
  
  subnet_id      = aws_subnet.envoy_poc_private_subnets[count.index].id
  route_table_id = aws_route_table.envoy_poc_private_rts[count.index].id
}
