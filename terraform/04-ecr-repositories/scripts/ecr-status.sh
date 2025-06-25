#!/bin/bash

# ECR Repository Status Check Script
# This script checks the status and details of ECR repositories

set -e

REGION=${1:-us-west-2}
PROFILE=${2:-avive-cfndev-k8s}
APP_REPO=${3:-cfndev-envoy-proxy-poc-app}
CLIENT_REPO=${4:-cfndev-envoy-proxy-poc-client}

echo "=== ECR Repository Status Check ==="
echo "Region: $REGION"
echo "Profile: $PROFILE"
echo ""

# Function to check repository status
check_repository() {
    local repo_name=$1
    echo "Checking repository: $repo_name"
    
    # Check if repository exists and get details
    local repo_info=$(aws ecr describe-repositories \
        --repository-names "$repo_name" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'repositories[0].{URI:repositoryUri,CreatedAt:createdAt,ImageCount:0}' \
        --output json 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo "✓ Repository exists"
        echo "  URI: $(echo "$repo_info" | jq -r '.URI')"
        echo "  Created: $(echo "$repo_info" | jq -r '.CreatedAt')"
        
        # Get image count
        local image_count=$(aws ecr list-images \
            --repository-name "$repo_name" \
            --region "$REGION" \
            --profile "$PROFILE" \
            --query 'length(imageIds)' \
            --output text 2>/dev/null || echo "0")
        
        echo "  Images: $image_count"
        
        # List recent images if any exist
        if [ "$image_count" -gt 0 ]; then
            echo "  Recent images:"
            aws ecr describe-images \
                --repository-name "$repo_name" \
                --region "$REGION" \
                --profile "$PROFILE" \
                --query 'sort_by(imageDetails, &imagePushedAt)[-3:].{Tags:imageTags[0],Size:imageSizeInBytes,Pushed:imagePushedAt}' \
                --output table 2>/dev/null || echo "    Unable to fetch image details"
        fi
    else
        echo "✗ Repository does not exist or is not accessible"
        return 1
    fi
    echo ""
}

# Check both repositories
echo "App Repository Status:"
check_repository "$APP_REPO"

echo "Client Repository Status:"
check_repository "$CLIENT_REPO"

echo "=== ECR Status Check Complete ==="
