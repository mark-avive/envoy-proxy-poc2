# EKS Cluster Security Group
resource "aws_security_group" "envoy_poc_eks_cluster_sg" {
  name_prefix = "${local.project_name}-eks-cluster-"
  description = "Security group for EKS cluster control plane"
  vpc_id      = aws_vpc.envoy_poc_vpc.id
  
  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-eks-cluster-sg"
    Purpose = "EKS-Cluster-SecurityGroup"
  })
}

# Worker Node Security Group
resource "aws_security_group" "envoy_poc_worker_node_sg" {
  name_prefix = "${local.project_name}-worker-node-"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.envoy_poc_vpc.id
  
  # Allow communication between worker nodes
  ingress {
    description = "Node to node communication"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }
  
  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-worker-node-sg"
    Purpose = "EKS-WorkerNode-SecurityGroup"
  })
}

# ALB Security Group
resource "aws_security_group" "envoy_poc_alb_sg" {
  name_prefix = "${local.project_name}-alb-"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.envoy_poc_vpc.id
  
  # Allow HTTP traffic from internet
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Allow HTTPS traffic from internet (for future use)
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-alb-sg"
    Purpose = "ALB-SecurityGroup"
  })
}

# Envoy Service Security Group
resource "aws_security_group" "envoy_poc_envoy_service_sg" {
  name_prefix = "${local.project_name}-envoy-service-"
  description = "Security group for Envoy proxy service"
  vpc_id      = aws_vpc.envoy_poc_vpc.id
  
  # Allow HTTP traffic from internet (through ALB)
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Allow Envoy admin interface access from VPC
  ingress {
    description = "Envoy admin interface from VPC"
    from_port   = 9901
    to_port     = 9901
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }
  
  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-envoy-service-sg"
    Purpose = "Envoy-Service-SecurityGroup"
  })
}

# Security Group Rules (defined separately to avoid circular dependencies)

# EKS Cluster Security Group Rules
resource "aws_security_group_rule" "eks_cluster_ingress_from_workers" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.envoy_poc_worker_node_sg.id
  security_group_id        = aws_security_group.envoy_poc_eks_cluster_sg.id
  description              = "HTTPS from worker nodes"
}

# Worker Node Security Group Rules
resource "aws_security_group_rule" "worker_node_ingress_from_cluster" {
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.envoy_poc_eks_cluster_sg.id
  security_group_id        = aws_security_group.envoy_poc_worker_node_sg.id
  description              = "Communication from EKS control plane"
}

resource "aws_security_group_rule" "worker_node_ingress_https_from_cluster" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.envoy_poc_eks_cluster_sg.id
  security_group_id        = aws_security_group.envoy_poc_worker_node_sg.id
  description              = "HTTPS to EKS control plane"
}

resource "aws_security_group_rule" "worker_node_ingress_from_alb" {
  type                     = "ingress"
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.envoy_poc_alb_sg.id
  security_group_id        = aws_security_group.envoy_poc_worker_node_sg.id
  description              = "Communication from ALB"
}

# ALB Security Group Rules
resource "aws_security_group_rule" "alb_egress_to_workers" {
  type                     = "egress"
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.envoy_poc_worker_node_sg.id
  security_group_id        = aws_security_group.envoy_poc_alb_sg.id
  description              = "To worker nodes NodePort range"
}

resource "aws_security_group_rule" "alb_egress_to_envoy" {
  type                     = "egress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.envoy_poc_envoy_service_sg.id
  security_group_id        = aws_security_group.envoy_poc_alb_sg.id
  description              = "To Envoy service"
}

# Envoy Service Security Group Rules
resource "aws_security_group_rule" "envoy_service_ingress_from_alb" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.envoy_poc_alb_sg.id
  security_group_id        = aws_security_group.envoy_poc_envoy_service_sg.id
  description              = "HTTP from ALB"
}

resource "aws_security_group_rule" "envoy_service_ingress_from_workers" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.envoy_poc_worker_node_sg.id
  security_group_id        = aws_security_group.envoy_poc_envoy_service_sg.id
  description              = "Internal communication from worker nodes"
}

resource "aws_security_group_rule" "envoy_service_egress_to_workers" {
  type                     = "egress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.envoy_poc_worker_node_sg.id
  security_group_id        = aws_security_group.envoy_poc_envoy_service_sg.id
  description              = "To server application"
}
