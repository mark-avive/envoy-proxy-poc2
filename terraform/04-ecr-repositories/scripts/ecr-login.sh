#!/bin/bash

# ECR Login Script
# This script logs into ECR registry for the specified region and profile

set -e

REGION=${1:-us-west-2}
PROFILE=${2:-avive-cfndev-k8s}

echo "=== ECR Login Script ==="
echo "Region: $REGION"
echo "Profile: $PROFILE"
echo ""

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
if [ $? -ne 0 ]; then
    echo "Error: Failed to get AWS account ID"
    exit 1
fi

echo "Account ID: $ACCOUNT_ID"

# Login to ECR
echo "Logging into ECR..."
aws ecr get-login-password --region "$REGION" --profile "$PROFILE" | \
    docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

if [ $? -eq 0 ]; then
    echo "✓ Successfully logged into ECR"
    echo "Registry: $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
else
    echo "✗ Failed to login to ECR"
    exit 1
fi
