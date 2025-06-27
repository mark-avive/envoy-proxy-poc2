#!/bin/bash

# Envoy Proxy Deployment Script
# This script deploys Envoy proxy to the EKS cluster

set -e

REGION=${1:-us-west-2}
PROFILE=${2:-avive-cfndev-k8s}
CLUSTER_NAME=${3:-envoy-poc}

echo "=== Envoy Proxy Kubernetes Deployment ==="
echo "Region: $REGION"
echo "Profile: $PROFILE"
echo "Cluster: $CLUSTER_NAME"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/../k8s"

# Check kubectl configuration
echo "Checking kubectl configuration..."
kubectl cluster-info > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: kubectl is not configured or cluster is not accessible"
    echo "Run: aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION --profile $PROFILE"
    exit 1
fi
echo "✓ kubectl is configured and cluster is accessible"

# Get networking information for ingress
echo "Getting networking information..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=envoy-vpc" --profile $PROFILE --region $REGION --query 'Vpcs[0].VpcId' --output text)
PUBLIC_SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*public*" --profile $PROFILE --region $REGION --query 'Subnets[].SubnetId' --output text | tr '\t' ',')
ALB_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=*alb*" "Name=vpc-id,Values=$VPC_ID" --profile $PROFILE --region $REGION --query 'SecurityGroups[0].GroupId' --output text)

echo "VPC ID: $VPC_ID"
echo "Public Subnets: $PUBLIC_SUBNETS"
echo "ALB Security Group: $ALB_SG"

# Prepare deployment manifest with substitutions
echo "Preparing Envoy deployment manifests..."
TEMP_MANIFEST="/tmp/envoy-deployment-$RANDOM.yaml"
cp "$K8S_DIR/deployment.yaml" "$TEMP_MANIFEST"

# Replace placeholders in the manifest
sed -i "s/\${PUBLIC_SUBNET_IDS}/$PUBLIC_SUBNETS/g" "$TEMP_MANIFEST"
sed -i "s/\${ALB_SECURITY_GROUP_ID}/$ALB_SG/g" "$TEMP_MANIFEST"

echo "Deployment manifest prepared: $TEMP_MANIFEST"

# Deploy to Kubernetes
echo "Deploying Envoy proxy to Kubernetes..."

# First apply the ConfigMap with templated configuration
echo "Applying templated Envoy configuration..."
kubectl create configmap envoy-config --from-file=envoy.yaml="$K8S_DIR/envoy-config.yaml" --dry-run=client -o yaml | kubectl apply -f -
if [ $? -ne 0 ]; then
    echo "Error: Failed to apply Envoy configuration"
    rm -f "$TEMP_MANIFEST"
    exit 1
fi

# Then apply the deployment manifest
kubectl apply -f "$TEMP_MANIFEST"
if [ $? -ne 0 ]; then
    echo "Error: Failed to deploy Envoy proxy"
    rm -f "$TEMP_MANIFEST"
    exit 1
fi
echo "✓ Kubernetes deployment applied successfully"

# Wait for ConfigMap and Deployment to be ready
echo "Waiting for Envoy deployment to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/envoy-proxy
if [ $? -ne 0 ]; then
    echo "Warning: Envoy deployment did not become ready within 5 minutes"
    echo "Checking pod status..."
    kubectl get pods -l app=envoy-proxy
    kubectl describe pods -l app=envoy-proxy
else
    echo "✓ Envoy deployment is ready"
fi

# Display deployment status
echo ""
echo "Deployment Status:"
echo "=================="
kubectl get deployments -l app=envoy-proxy
echo ""
kubectl get services -l app=envoy-proxy
echo ""
kubectl get ingress -l app=envoy-proxy
echo ""
kubectl get pods -l app=envoy-proxy -o wide

# Clean up temp file
rm -f "$TEMP_MANIFEST"

echo ""
echo "✓ Envoy proxy deployment completed successfully"
echo ""
echo "Next: Wait for ALB to be provisioned (this may take 2-3 minutes)"
echo "Check ALB status: kubectl get ingress envoy-proxy-ingress"
