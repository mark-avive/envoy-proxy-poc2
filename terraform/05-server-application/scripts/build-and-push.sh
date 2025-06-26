#!/bin/bash

# Docker Build and Push Script for Server Application
# This script builds the WebSocket server Docker image and pushes it to ECR

set -e

REGION=${1:-us-west-2}
PROFILE=${2:-avive-cfndev-k8s}
ECR_REPO_NAME=${3:-cfndev-envoy-proxy-poc-app}
IMAGE_TAG=${4:-latest}

echo "=== Server Application Build and Push ==="
echo "Region: $REGION"
echo "Profile: $PROFILE"
echo "ECR Repository: $ECR_REPO_NAME"
echo "Image Tag: $IMAGE_TAG"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR/../app"

# Get AWS account ID
echo "Getting AWS account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
if [ $? -ne 0 ]; then
    echo "Error: Failed to get AWS account ID"
    exit 1
fi

ECR_REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
ECR_REPO_URL="$ECR_REGISTRY/$ECR_REPO_NAME"

echo "Account ID: $ACCOUNT_ID"
echo "ECR Registry: $ECR_REGISTRY"
echo "ECR Repository URL: $ECR_REPO_URL"
echo ""

# Check if Docker is running
echo "Checking Docker status..."
docker info > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Docker is not running or not accessible"
    exit 1
fi
echo "✓ Docker is running"

# Login to ECR
echo "Logging into ECR..."
aws ecr get-login-password --region "$REGION" --profile "$PROFILE" | \
    docker login --username AWS --password-stdin "$ECR_REGISTRY"

if [ $? -ne 0 ]; then
    echo "Error: Failed to login to ECR"
    exit 1
fi
echo "✓ Successfully logged into ECR"

# Build Docker image
echo "Building Docker image..."
cd "$APP_DIR"

docker build -t "$ECR_REPO_URL:$IMAGE_TAG" . \
    --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
    --build-arg VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown") \
    --build-arg VERSION="1.0.0"

if [ $? -ne 0 ]; then
    echo "Error: Docker build failed"
    exit 1
fi
echo "✓ Docker image built successfully"

# Create timestamp for consistent tagging
TIMESTAMP_TAG=$(date +%Y%m%d-%H%M%S)

# Tag image with additional tags
echo "Tagging image..."
docker tag "$ECR_REPO_URL:$IMAGE_TAG" "$ECR_REPO_URL:$TIMESTAMP_TAG"

# Get image details
IMAGE_SIZE=$(docker images "$ECR_REPO_URL:$IMAGE_TAG" --format "table {{.Size}}" | tail -n 1)
echo "Image size: $IMAGE_SIZE"

# Push image to ECR
echo "Pushing image to ECR..."
docker push "$ECR_REPO_URL:$IMAGE_TAG"

if [ $? -ne 0 ]; then
    echo "Error: Failed to push image to ECR"
    exit 1
fi

# Push timestamped tag as well
docker push "$ECR_REPO_URL:$TIMESTAMP_TAG"

echo "✓ Image pushed successfully to ECR"
echo ""

# Display image information
echo "Image Information:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Repository: $ECR_REPO_URL"
echo "Tag: $IMAGE_TAG"
echo "Size: $IMAGE_SIZE"
echo "Registry: $ECR_REGISTRY"
echo ""

# List recent images in the repository
echo "Recent images in repository:"
aws ecr describe-images \
    --repository-name "$ECR_REPO_NAME" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'sort_by(imageDetails, &imagePushedAt)[-5:].{Tags:imageTags[0],Size:imageSizeInBytes,Pushed:imagePushedAt}' \
    --output table 2>/dev/null || echo "Unable to list images"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "=== Build and Push Complete ==="
echo ""
echo "Next steps:"
echo "1. Update Kubernetes deployment with image: $ECR_REPO_URL:$IMAGE_TAG"
echo "2. Deploy to EKS cluster: kubectl apply -f k8s/deployment.yaml"
echo "3. Check deployment status: kubectl get pods -l app=envoy-poc-app-server"
