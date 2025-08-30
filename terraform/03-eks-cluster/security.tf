# Security group rule to allow ALB to access EKS cluster-managed security group
resource "aws_security_group_rule" "eks_cluster_managed_sg_ingress_from_alb" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.envoy_poc_alb_sg.id
  security_group_id        = data.aws_eks_cluster.envoy_poc_cluster.vpc_config[0].cluster_security_group_id
  description              = "Allow ALB to access Envoy pods on EKS cluster security group"
}


# Security group rule to allow ALB health checks to EKS cluster-managed security group
resource "aws_security_group_rule" "eks_cluster_managed_sg_ingress_healthcheck_from_alb" {
  type                     = "ingress"
  from_port                = 9901
  to_port                  = 9901
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.envoy_poc_alb_sg.id
  security_group_id        = data.aws_eks_cluster.envoy_poc_cluster.vpc_config[0].cluster_security_group_id
  description              = "Allow ALB health checks to Envoy admin interface"
}

# Data source to get EKS cluster information
data "aws_eks_cluster" "envoy_poc_cluster" {
  name = "${local.project_name}"
}
