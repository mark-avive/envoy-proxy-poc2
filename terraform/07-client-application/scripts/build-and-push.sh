#!/bin/bash
set -e

# WebSocket Client Application - Build and Push to ECR
echo "=== Building and Pushing WebSocket Client Application ==="

# Configuration
REGION=${AWS_REGION:-us-west-2}
PROFILE=${AWS_PROFILE:-avive-cfndev-k8s}
ECR_REPOSITORY=${ECR_REPOSITORY}
IMAGE_TAG=${IMAGE_TAG:-latest}

if [ -z "$ECR_REPOSITORY" ]; then
    echo "❌ Error: ECR_REPOSITORY environment variable is required"
    exit 1
fi

echo "Region: $REGION"
echo "Profile: $PROFILE"
echo "ECR Repository: $ECR_REPOSITORY"
echo "Image Tag: $IMAGE_TAG"

# Login to ECR
echo "Logging in to Amazon ECR..."
aws ecr get-login-password --region $REGION --profile $PROFILE | docker login --username AWS --password-stdin $ECR_REPOSITORY

# Build Docker image
echo "Building Docker image..."
cd app
docker build -t websocket-client:$IMAGE_TAG .

# Tag image for ECR
echo "Tagging image for ECR..."
docker tag websocket-client:$IMAGE_TAG $ECR_REPOSITORY:$IMAGE_TAG

# Push image to ECR
echo "Pushing image to ECR..."
docker push $ECR_REPOSITORY:$IMAGE_TAG

echo "✅ Docker image built and pushed successfully!"
echo "Image URI: $ECR_REPOSITORY:$IMAGE_TAG"
