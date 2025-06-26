# CloudWatch Log Group for EKS Cluster
resource "aws_cloudwatch_log_group" "envoy_poc_eks_cluster_logs" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = 7
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-eks-cluster-logs"
  })
}

# EKS Cluster
resource "aws_eks_cluster" "envoy_poc_eks_cluster" {
  name     = local.cluster_name
  role_arn = aws_iam_role.envoy_poc_eks_cluster_role.arn
  version  = local.cluster_version

  vpc_config {
    subnet_ids              = concat(
      data.terraform_remote_state.networking.outputs.private_subnet_ids,
      data.terraform_remote_state.networking.outputs.public_subnet_ids
    )
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [
      data.terraform_remote_state.networking.outputs.eks_cluster_security_group_id
    ]
  }

  # Enable Control Plane Logging
  enabled_cluster_log_types = local.cluster_log_types

  # Ensure that IAM Role permissions are created before and deleted after EKS Cluster handling.
  depends_on = [
    aws_iam_role_policy_attachment.envoy_poc_eks_cluster_policy,
    aws_cloudwatch_log_group.envoy_poc_eks_cluster_logs,
  ]

  tags = merge(local.common_tags, {
    Name = local.cluster_name
  })
}

# EKS Node Group
resource "aws_eks_node_group" "envoy_poc_eks_nodes" {
  cluster_name    = aws_eks_cluster.envoy_poc_eks_cluster.name
  node_group_name = local.node_group_name
  node_role_arn   = aws_iam_role.envoy_poc_eks_node_group_role.arn
  subnet_ids      = data.terraform_remote_state.networking.outputs.private_subnet_ids
  ami_type        = local.node_ami_type
  instance_types  = [local.node_instance_type]

  scaling_config {
    desired_size = local.node_desired_capacity
    max_size     = local.node_max_capacity
    min_size     = local.node_min_capacity
  }

  update_config {
    max_unavailable = 1
  }

  # Allow external changes without Terraform plan difference
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  depends_on = [
    aws_iam_role_policy_attachment.envoy_poc_eks_worker_node_policy,
    aws_iam_role_policy_attachment.envoy_poc_eks_cni_policy,
    aws_iam_role_policy_attachment.envoy_poc_eks_container_registry_policy,
  ]

  tags = merge(local.common_tags, {
    Name = local.node_group_name
  })
}

# OIDC Provider for EKS cluster (required for IRSA - IAM Roles for Service Accounts)
data "tls_certificate" "eks_cluster_oidc" {
  url = aws_eks_cluster.envoy_poc_eks_cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks_cluster_oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_cluster_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.envoy_poc_eks_cluster.identity[0].oidc[0].issuer

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-oidc-provider"
  })
}
