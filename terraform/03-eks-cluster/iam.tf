# EKS Cluster Service Role
resource "aws_iam_role" "envoy_poc_eks_cluster_role" {
  name = "${local.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-eks-cluster-role"
  })
}

# Attach required policies to EKS cluster role
resource "aws_iam_role_policy_attachment" "envoy_poc_eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.envoy_poc_eks_cluster_role.name
}

# EKS Node Group Service Role
resource "aws_iam_role" "envoy_poc_eks_node_group_role" {
  name = "${local.project_name}-eks-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-eks-node-group-role"
  })
}

# Attach required policies to EKS node group role
resource "aws_iam_role_policy_attachment" "envoy_poc_eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.envoy_poc_eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "envoy_poc_eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.envoy_poc_eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "envoy_poc_eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.envoy_poc_eks_node_group_role.name
}
