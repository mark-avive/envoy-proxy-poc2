#!/bin/bash

# Cleanup script for Envoy Proxy deployment
# This script removes Envoy resources from the cluster

set -e

echo "=== Cleaning up Envoy Proxy resources ==="

# Delete Envoy resources
echo "Deleting Envoy proxy resources..."
kubectl delete ingress envoy-proxy-ingress --ignore-not-found=true
kubectl delete service envoy-proxy-service --ignore-not-found=true
kubectl delete deployment envoy-proxy --ignore-not-found=true
kubectl delete configmap envoy-config --ignore-not-found=true

echo "✓ Envoy proxy resources deleted"

# Note: ALB Controller and its resources are managed by Helm and will be cleaned up by terraform
echo "Note: AWS Load Balancer Controller will be cleaned up by terraform"
