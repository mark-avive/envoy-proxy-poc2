# EKS Cluster Security Group
resource "aws_security_group" "envoy_poc_eks_cluster_sg" {
  name_prefix = "${local.project_name}-eks-cluster-"
  description = "Security group for EKS cluster control plane"
  vpc_id      = aws_vpc.envoy_poc_vpc.id
  
  # All rules are managed as separate resources
  
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
  
  # All rules are managed as separate resources
  
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

resource "aws_security_group_rule" "eks_cluster_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.envoy_poc_eks_cluster_sg.id
  description       = "All outbound traffic"
}

# Worker Node Security Group Rules
resource "aws_security_group_rule" "worker_node_ingress_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.envoy_poc_worker_node_sg.id
  description       = "Node to node communication"
}

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

resource "aws_security_group_rule" "worker_node_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.envoy_poc_worker_node_sg.id
  description       = "All outbound traffic"
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
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.envoy_poc_envoy_service_sg.id
  security_group_id        = aws_security_group.envoy_poc_alb_sg.id
  description              = "To Envoy service"
}

# ALB ingress rules (previously inline)
resource "aws_security_group_rule" "alb_ingress_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.envoy_poc_alb_sg.id
  description       = "HTTP from internet"
}

resource "aws_security_group_rule" "alb_ingress_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.envoy_poc_alb_sg.id
  description       = "HTTPS from internet"
}

resource "aws_security_group_rule" "alb_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.envoy_poc_alb_sg.id
  description       = "All outbound traffic"
}

# Envoy Service ingress rules (previously inline)
resource "aws_security_group_rule" "envoy_service_ingress_admin" {
  type              = "ingress"
  from_port         = 9901
  to_port           = 9901
  protocol          = "tcp"
  cidr_blocks       = [local.vpc_cidr]
  security_group_id = aws_security_group.envoy_poc_envoy_service_sg.id
  description       = "Envoy admin interface from VPC"
}

resource "aws_security_group_rule" "envoy_service_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.envoy_poc_envoy_service_sg.id
  description       = "All outbound traffic"
}

resource "aws_security_group_rule" "envoy_service_ingress_from_alb" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.envoy_poc_alb_sg.id
  security_group_id        = aws_security_group.envoy_poc_envoy_service_sg.id
  description              = "HTTP from ALB"
}

resource "aws_security_group_rule" "envoy_service_ingress_from_workers" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
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





