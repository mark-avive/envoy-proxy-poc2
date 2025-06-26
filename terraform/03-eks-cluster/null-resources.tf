# Null Resources for EKS cluster post-deployment configuration

# Configure kubectl for EKS cluster
resource "null_resource" "configure_kubeconfig" {
  depends_on = [aws_eks_cluster.envoy_poc_eks_cluster]

  triggers = {
    cluster_name     = aws_eks_cluster.envoy_poc_eks_cluster.name
    cluster_endpoint = aws_eks_cluster.envoy_poc_eks_cluster.endpoint
    cluster_arn      = aws_eks_cluster.envoy_poc_eks_cluster.arn
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Configuring kubectl for EKS cluster ==="
      
      # Determine kubeconfig path: use KUBECONFIG env var if set, otherwise use terraform variable
      KUBECONFIG_PATH="${var.kubeconfig_path != "" ? var.kubeconfig_path : ""}"
      if [ -z "$KUBECONFIG_PATH" ] && [ -n "$KUBECONFIG" ]; then
        KUBECONFIG_PATH="$KUBECONFIG"
        echo "Using KUBECONFIG environment variable: $KUBECONFIG_PATH"
      elif [ -z "$KUBECONFIG_PATH" ]; then
        KUBECONFIG_PATH="/home/mark/.kube/config-cfndev-envoy-poc"
        echo "Using default kubeconfig path: $KUBECONFIG_PATH"
      else
        echo "Using provided kubeconfig path: $KUBECONFIG_PATH"
      fi
      
      # Ensure the .kube directory exists
      mkdir -p "$(dirname "$KUBECONFIG_PATH")"
      
      # Configure kubeconfig for the EKS cluster
      aws eks update-kubeconfig \
        --name ${aws_eks_cluster.envoy_poc_eks_cluster.name} \
        --region ${local.aws_region} \
        --profile ${local.aws_profile} \
        --kubeconfig "$KUBECONFIG_PATH"
      
      # Verify the configuration
      export KUBECONFIG="$KUBECONFIG_PATH"
      kubectl cluster-info
      
      echo "✓ Kubeconfig configured successfully at: $KUBECONFIG_PATH"
      echo "✓ To use this configuration, run: export KUBECONFIG=$KUBECONFIG_PATH"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "=== Cleaning up kubeconfig ==="
      
      # Determine kubeconfig path: use KUBECONFIG env var if set
      KUBECONFIG_PATH="$KUBECONFIG"
      if [ -z "$KUBECONFIG_PATH" ]; then
        KUBECONFIG_PATH="/home/mark/.kube/config-cfndev-envoy-poc"
      fi
      
      # Remove the specific kubeconfig file if it exists
      if [ -f "$KUBECONFIG_PATH" ]; then
        rm -f "$KUBECONFIG_PATH"
        echo "✓ Removed kubeconfig file: $KUBECONFIG_PATH"
      fi
    EOT
  }
}

# Wait for node group to be ready
resource "null_resource" "wait_for_node_group" {
  depends_on = [
    aws_eks_node_group.envoy_poc_eks_nodes,
    null_resource.configure_kubeconfig
  ]

  triggers = {
    node_group_arn = aws_eks_node_group.envoy_poc_eks_nodes.arn
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Waiting for node group to be ready ==="
      
      # Determine kubeconfig path: use KUBECONFIG env var if set
      KUBECONFIG_PATH="$KUBECONFIG"
      if [ -z "$KUBECONFIG_PATH" ]; then
        KUBECONFIG_PATH="/home/mark/.kube/config-cfndev-envoy-poc"
      fi
      
      export KUBECONFIG="$KUBECONFIG_PATH"
      
      # Wait for nodes to be ready (up to 10 minutes)
      timeout=600
      interval=15
      elapsed=0
      
      while [ $elapsed -lt $timeout ]; do
        echo "Checking node status... ($${elapsed}s elapsed)"
        
        if kubectl get nodes --no-headers 2>/dev/null | grep -q Ready; then
          echo "✓ Nodes are ready!"
          kubectl get nodes
          break
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
      done
      
      if [ $elapsed -ge $timeout ]; then
        echo "⚠ Timeout waiting for nodes to be ready"
        exit 1
      fi
      
      echo "✓ EKS cluster and nodes are ready for deployments"
    EOT
  }
}
