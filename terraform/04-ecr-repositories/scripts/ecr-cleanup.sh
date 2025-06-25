#!/bin/bash

# ECR Repository Cleanup Script
# This script can be used to clean up ECR repositories (called during destroy)

set -e

REGION=${1:-us-west-2}
PROFILE=${2:-avive-cfndev-k8s}
APP_REPO=${3:-cfndev-envoy-proxy-poc-app}
CLIENT_REPO=${4:-cfndev-envoy-proxy-poc-client}

echo "=== ECR Repository Cleanup ==="
echo "Region: $REGION"
echo "Profile: $PROFILE"
echo ""

# Function to clean up repository images
cleanup_repository() {
    local repo_name=$1
    echo "Cleaning up repository: $repo_name"
    
    # Check if repository exists
    aws ecr describe-repositories \
        --repository-names "$repo_name" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'repositories[0].repositoryName' \
        --output text >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        # Get all images in the repository
        local images=$(aws ecr list-images \
            --repository-name "$repo_name" \
            --region "$REGION" \
            --profile "$PROFILE" \
            --query 'imageIds[*]' \
            --output json 2>/dev/null)
        
        if [ "$images" != "[]" ] && [ "$images" != "null" ]; then
            echo "  Deleting images from $repo_name..."
            aws ecr batch-delete-image \
                --repository-name "$repo_name" \
                --region "$REGION" \
                --profile "$PROFILE" \
                --image-ids "$images" \
                --output text >/dev/null 2>&1
            
            if [ $? -eq 0 ]; then
                echo "  ✓ Images deleted successfully"
            else
                echo "  ✗ Failed to delete some images"
            fi
        else
            echo "  No images to delete"
        fi
    else
        echo "  Repository $repo_name does not exist"
    fi
    echo ""
}

# Only clean up if this is a destroy operation
if [ "${CLEANUP_MODE:-false}" = "true" ]; then
    echo "WARNING: Cleanup mode enabled - this will delete all images!"
    echo "Proceeding in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
    
    cleanup_repository "$APP_REPO"
    cleanup_repository "$CLIENT_REPO"
else
    echo "Cleanup mode not enabled. Set CLEANUP_MODE=true to perform cleanup."
fi

echo "=== ECR Cleanup Complete ==="
