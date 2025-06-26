#!/bin/bash

# Environment Setup Script for Envoy Proxy POC
# This script configures the environment variables for AWS and kubectl

echo "=== Envoy Proxy POC Environment Setup ==="

# AWS Configuration
export AWS_PROFILE=avive-cfndev-k8s

# Kubectl Configuration - use existing KUBECONFIG or set default
if [ -z "$KUBECONFIG" ]; then
    export KUBECONFIG=/home/mark/.kube/config-cfndev-envoy-poc
fi

echo "Environment variables configured:"
echo "  AWS_PROFILE=$AWS_PROFILE"
echo "  KUBECONFIG=$KUBECONFIG"
echo ""

# Verify AWS CLI access
echo "Verifying AWS CLI access..."
if aws sts get-caller-identity --profile "$AWS_PROFILE" > /dev/null 2>&1; then
    echo "✓ AWS CLI profile '$AWS_PROFILE' is accessible"
    AWS_ACCOUNT=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
    echo "  Account ID: $AWS_ACCOUNT"
else
    echo "✗ AWS CLI profile '$AWS_PROFILE' is not accessible"
    echo "  Please configure your AWS SSO profile first"
fi
echo ""

# Verify kubectl access
echo "Verifying kubectl access..."
if [ -f "$KUBECONFIG" ]; then
    echo "✓ Kubeconfig file exists at: $KUBECONFIG"
    if kubectl cluster-info > /dev/null 2>&1; then
        echo "✓ kubectl connection to EKS cluster successful"
        CLUSTER_NAME=$(kubectl config current-context | cut -d'/' -f2 2>/dev/null || echo "unknown")
        echo "  Current cluster: $CLUSTER_NAME"
    else
        echo "✗ kubectl connection failed"
        echo "  The kubeconfig file exists but cluster is not accessible"
    fi
else
    echo "✗ Kubeconfig file not found at: $KUBECONFIG"
    echo "  Deploy the EKS cluster first: cd terraform/03-eks-cluster && ./deploy.sh apply"
fi
echo ""

echo "To use these settings in your current shell session:"
echo "  source $(realpath "$0")"
echo ""
echo "To make these settings persistent, add the following to your ~/.bashrc or ~/.zshrc:"
echo "  export AWS_PROFILE=avive-cfndev-k8s"
echo "  export KUBECONFIG=/home/mark/.kube/config-cfndev-envoy-poc  # or your preferred path"
