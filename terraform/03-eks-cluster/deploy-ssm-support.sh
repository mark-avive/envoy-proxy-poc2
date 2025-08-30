#!/bin/bash

# Deploy script for updating EKS cluster with SSM Agent support
# This script should be run from the terraform/03-eks-cluster directory

set -e

echo "=== Updating EKS Cluster with SSM Agent Support ==="
echo

# Check if we're in the correct directory
if [ ! -f "eks.tf" ]; then
    echo "Error: Please run this script from the terraform/03-eks-cluster directory"
    exit 1
fi

echo "1. First, updating the networking layer to add VPC endpoints..."
cd ../02-networking
terraform init
terraform plan -out=networking.tfplan
read -p "Do you want to apply the networking changes? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    terraform apply networking.tfplan
    echo "✓ Networking layer updated successfully"
else
    echo "Skipping networking changes"
fi

echo
echo "2. Now updating the EKS cluster with SSM policies..."
cd ../03-eks-cluster
terraform init
terraform plan -out=eks.tfplan
read -p "Do you want to apply the EKS cluster changes? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    terraform apply eks.tfplan
    echo "✓ EKS cluster updated successfully"
else
    echo "Skipping EKS cluster changes"
fi

echo
echo "=== Deployment Summary ==="
echo "The following changes have been made to enable SSM Agent:"
echo "1. Added VPC endpoints for SSM services (ssm, ssmmessages, ec2messages)"
echo "2. Added IAM policies to EKS node group role:"
echo "   - AmazonSSMManagedInstanceCore"
echo "   - CloudWatchAgentServerPolicy"
echo "   - AmazonSSMPatchAssociation"
echo "3. Updated node group dependencies to include SSM policies"
echo
echo "After applying these changes, your EKS nodes should be able to:"
echo "- Connect to Systems Manager"
echo "- Register with SSM Agent"
echo "- Support Session Manager for secure shell access"
echo "- Support Systems Manager Run Command"
echo "- Support Systems Manager Patch Manager"
echo
echo "To verify SSM Agent is working:"
echo "1. Go to AWS Console -> Systems Manager -> Session Manager"
echo "2. You should see your EKS nodes listed as managed instances"
echo "3. You can start sessions directly to the nodes if needed"
echo
echo "✓ SSM Agent configuration complete!"
