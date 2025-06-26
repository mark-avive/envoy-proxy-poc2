# EKS Cluster Outputs
output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.envoy_poc_eks_cluster.cluster_id
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.envoy_poc_eks_cluster.arn
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.envoy_poc_eks_cluster.name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.envoy_poc_eks_cluster.endpoint
}

output "cluster_version" {
  description = "EKS cluster version"
  value       = aws_eks_cluster.envoy_poc_eks_cluster.version
}

output "cluster_platform_version" {
  description = "Platform version for the EKS cluster"
  value       = aws_eks_cluster.envoy_poc_eks_cluster.platform_version
}

output "cluster_status" {
  description = "Status of the EKS cluster"
  value       = aws_eks_cluster.envoy_poc_eks_cluster.status
}

output "cluster_security_group_id" {
  description = "Cluster security group that was created by Amazon EKS for the cluster"
  value       = aws_eks_cluster.envoy_poc_eks_cluster.vpc_config[0].cluster_security_group_id
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.envoy_poc_eks_cluster.certificate_authority[0].data
}

# Node Group Outputs
output "node_group_arn" {
  description = "Amazon Resource Name (ARN) of the EKS Node Group"
  value       = aws_eks_node_group.envoy_poc_eks_nodes.arn
}

output "node_group_status" {
  description = "Status of the EKS Node Group"
  value       = aws_eks_node_group.envoy_poc_eks_nodes.status
}

output "node_group_capacity_type" {
  description = "Type of capacity associated with the EKS Node Group"
  value       = aws_eks_node_group.envoy_poc_eks_nodes.capacity_type
}

# IAM Role Outputs
output "cluster_iam_role_name" {
  description = "IAM role name associated with EKS cluster"
  value       = aws_iam_role.envoy_poc_eks_cluster_role.name
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN associated with EKS cluster"
  value       = aws_iam_role.envoy_poc_eks_cluster_role.arn
}

output "node_group_iam_role_name" {
  description = "IAM role name associated with EKS node group"
  value       = aws_iam_role.envoy_poc_eks_node_group_role.name
}

output "node_group_iam_role_arn" {
  description = "IAM role ARN associated with EKS node group"
  value       = aws_iam_role.envoy_poc_eks_node_group_role.arn
}

# CloudWatch Log Group Output
output "cluster_cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for EKS cluster logs"
  value       = aws_cloudwatch_log_group.envoy_poc_eks_cluster_logs.name
}

# OIDC Provider Output (for future use with AWS Load Balancer Controller)
output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = aws_eks_cluster.envoy_poc_eks_cluster.identity[0].oidc[0].issuer
}

output "cluster_oidc_provider_arn" {
  description = "ARN of the OIDC Provider for the EKS cluster"
  value       = aws_iam_openid_connect_provider.eks_cluster_oidc.arn
}

# Kubectl Configuration
output "kubectl_config" {
  description = "kubectl config command to configure access to the cluster"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.envoy_poc_eks_cluster.name} --region ${local.aws_region} --profile ${local.aws_profile}"
}

output "kubeconfig_path" {
  description = "Path to the kubeconfig file for this EKS cluster"
  value       = local.kubeconfig_path
}

output "kubeconfig_export_command" {
  description = "Environment variable export command for KUBECONFIG"
  value       = "export KUBECONFIG=${local.kubeconfig_path}"
}
