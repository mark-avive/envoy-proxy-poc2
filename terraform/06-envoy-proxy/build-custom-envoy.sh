#!/bin/bash

# Build and push custom Envoy image with lua-resty-redis support
# This script builds a custom Envoy image that includes direct Redis connectivity
# All configuration is sourced from build-config.env

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/build-config.env"

# Function to display usage information
usage() {
    echo "Usage: $0 [IMAGE_TAG] [OPTIONS]"
    echo ""
    echo "Arguments:"
    echo "  IMAGE_TAG    Docker image tag (defaults to DEFAULT_IMAGE_TAG from config)"
    echo ""
    echo "Options:"
    echo "  --force      Force rebuild even if image exists"
    echo "  --no-push    Build only, don't push to ECR"
    echo "  --cleanup    Clean up local images after push"
    echo "  --help       Show this help message"
    echo ""
    echo "Configuration is loaded from: $CONFIG_FILE"
    exit 1
}

# Parse command line arguments
IMAGE_TAG=""
FORCE_BUILD="false"
NO_PUSH="false"
CLEANUP_AFTER="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_BUILD="true"
            shift
            ;;
        --no-push)
            NO_PUSH="true"
            shift
            ;;
        --cleanup)
            CLEANUP_AFTER="true"
            shift
            ;;
        --help)
            usage
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            if [[ -z "$IMAGE_TAG" ]]; then
                IMAGE_TAG="$1"
            else
                echo "Multiple image tags provided. Using: $IMAGE_TAG"
            fi
            shift
            ;;
    esac
done

# Load configuration from file
if [[ -f "$CONFIG_FILE" ]]; then
    echo "📋 Loading configuration from: $CONFIG_FILE"
    source "$CONFIG_FILE"
else
    echo "❌ Configuration file not found: $CONFIG_FILE"
    echo "Please create the configuration file with required variables."
    echo "Run '$0 --help' for usage information."
    exit 1
fi

# Use default tag if not provided via command line
IMAGE_TAG="${IMAGE_TAG:-$DEFAULT_IMAGE_TAG}"

# Override config file settings with command line options
if [[ "$FORCE_BUILD" == "true" ]]; then
    FORCE_REBUILD="true"
fi

if [[ "$CLEANUP_AFTER" == "true" ]]; then
    CLEANUP_LOCAL_IMAGE="true"
fi

echo "=== Building Custom Envoy Image with Redis Support ==="
echo "📝 Configuration:"
echo "   Config file: $CONFIG_FILE"
echo "   Dockerfile: $DOCKERFILE_NAME"
echo "   Base image: $BASE_ENVOY_IMAGE"
echo "   Repository: $ECR_REPOSITORY"
echo "   Tag: $IMAGE_TAG"
echo "   Platform: $BUILD_PLATFORM"
echo "   Force rebuild: $FORCE_REBUILD"
echo "   Scanning enabled: $ENABLE_SCANNING"

# Validate required variables
required_vars=("AWS_REGION" "AWS_PROFILE" "ECR_REPOSITORY" "DOCKERFILE_NAME")
for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        echo "❌ Required variable $var is not set in $CONFIG_FILE"
        exit 1
    fi
done

# Check if Dockerfile exists
if [[ ! -f "$SCRIPT_DIR/$DOCKERFILE_NAME" ]]; then
    echo "❌ Dockerfile not found: $SCRIPT_DIR/$DOCKERFILE_NAME"
    exit 1
fi

# Get AWS account ID
echo "🔍 Getting AWS account information..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
if [[ $? -ne 0 ]]; then
    echo "❌ Failed to get AWS account ID. Check your AWS profile: $AWS_PROFILE"
    exit 1
fi

ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"

# Check if image already exists (unless force rebuild)
if [[ "$FORCE_REBUILD" != "true" ]]; then
    echo "🔍 Checking if image already exists..."
    if docker image inspect "${ECR_REPOSITORY}:${IMAGE_TAG}" >/dev/null 2>&1; then
        echo "⚠️  Image ${ECR_REPOSITORY}:${IMAGE_TAG} already exists locally"
        echo "   Use --force to rebuild anyway"
    fi
fi

# Build the Docker image
echo "🏗️  Building custom Envoy image..."
BUILD_CMD="docker build -f $SCRIPT_DIR/$DOCKERFILE_NAME"

# Add platform if specified
if [[ -n "$BUILD_PLATFORM" ]]; then
    BUILD_CMD="$BUILD_CMD --platform $BUILD_PLATFORM"
fi

# Add build args if specified
if [[ -n "$DOCKER_BUILD_ARGS" ]]; then
    BUILD_CMD="$BUILD_CMD $DOCKER_BUILD_ARGS"
fi

# Add build arg for base image
BUILD_CMD="$BUILD_CMD --build-arg BASE_IMAGE=$BASE_ENVOY_IMAGE"

# Add tag and context
BUILD_CMD="$BUILD_CMD -t ${ECR_REPOSITORY}:${IMAGE_TAG} $SCRIPT_DIR"

echo "🔨 Executing: $BUILD_CMD"
eval "$BUILD_CMD"

if [[ $? -ne 0 ]]; then
    echo "❌ Docker build failed"
    exit 1
fi

echo "✅ Docker image built successfully"

# Tag additional tags if specified
if [[ -n "$ADDITIONAL_TAGS" ]]; then
    echo "🏷️  Tagging additional versions..."
    for tag in $ADDITIONAL_TAGS; do
        echo "   Tagging as: $tag"
        docker tag "${ECR_REPOSITORY}:${IMAGE_TAG}" "${ECR_REPOSITORY}:${tag}"
    done
fi

# Exit early if no-push option is set
if [[ "$NO_PUSH" == "true" ]]; then
    echo "🚫 Skipping push to ECR (--no-push specified)"
    echo "✅ Local build completed successfully"
    echo ""
    echo "🎯 Local image ready:"
    echo "   ${ECR_REPOSITORY}:${IMAGE_TAG}"
    exit 0
fi

# Check if ECR repository exists, create if not
echo "🔍 Checking ECR repository..."
if ! aws ecr describe-repositories --repository-names "$ECR_REPOSITORY" --region "$AWS_REGION" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
    echo "📦 Creating ECR repository: $ECR_REPOSITORY"
    
    # Build ECR create command based on configuration
    CREATE_CMD="aws ecr create-repository --repository-name $ECR_REPOSITORY --region $AWS_REGION --profile $AWS_PROFILE"
    
    if [[ "$ENABLE_SCANNING" == "true" ]]; then
        CREATE_CMD="$CREATE_CMD --image-scanning-configuration scanOnPush=true"
    fi
    
    eval "$CREATE_CMD"
    
    if [[ $? -eq 0 ]]; then
        echo "✅ ECR repository created successfully"
    else
        echo "❌ Failed to create ECR repository"
        exit 1
    fi
else
    echo "✅ ECR repository already exists"
fi

# Login to ECR
echo "🔐 Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" --profile "$AWS_PROFILE" | \
    docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

if [[ $? -ne 0 ]]; then
    echo "❌ ECR login failed"
    exit 1
fi

# Tag and push the image
echo "🚀 Pushing image to ECR..."
docker tag "${ECR_REPOSITORY}:${IMAGE_TAG}" "${ECR_URI}:${IMAGE_TAG}"
docker push "${ECR_URI}:${IMAGE_TAG}"

PUSH_SUCCESS=$?

# Push additional tags if they exist
if [[ -n "$ADDITIONAL_TAGS" && $PUSH_SUCCESS -eq 0 ]]; then
    echo "🚀 Pushing additional tags..."
    for tag in $ADDITIONAL_TAGS; do
        echo "   Pushing tag: $tag"
        docker tag "${ECR_REPOSITORY}:${tag}" "${ECR_URI}:${tag}"
        docker push "${ECR_URI}:${tag}"
        if [[ $? -ne 0 ]]; then
            echo "⚠️  Failed to push tag: $tag"
        fi
    done
fi

if [[ $PUSH_SUCCESS -eq 0 ]]; then
    echo "✅ Image pushed successfully!"
    echo ""
    echo "🎯 Custom Envoy image is ready:"
    echo "   ${ECR_URI}:${IMAGE_TAG}"
    
    if [[ -n "$ADDITIONAL_TAGS" ]]; then
        echo ""
        echo "📦 Additional tags available:"
        for tag in $ADDITIONAL_TAGS; do
            echo "   ${ECR_URI}:${tag}"
        done
    fi
    
    echo ""
    echo "📝 Update your deployment to use this image:"
    echo "   image: ${ECR_URI}:${IMAGE_TAG}"
    
    # Cleanup if requested
    if [[ "$CLEANUP_LOCAL_IMAGE" == "true" ]]; then
        echo ""
        echo "🧹 Cleaning up local images..."
        docker rmi "${ECR_REPOSITORY}:${IMAGE_TAG}" >/dev/null 2>&1 || true
        
        if [[ -n "$ADDITIONAL_TAGS" ]]; then
            for tag in $ADDITIONAL_TAGS; do
                docker rmi "${ECR_REPOSITORY}:${tag}" >/dev/null 2>&1 || true
            done
        fi
        
        echo "✅ Local images cleaned up"
    fi
    
    # Prune dangling images if requested
    if [[ "$PRUNE_DANGLING_IMAGES" == "true" ]]; then
        echo ""
        echo "🧹 Pruning dangling Docker images..."
        docker image prune -f >/dev/null 2>&1 || true
        echo "✅ Dangling images pruned"
    fi
    
else
    echo "❌ Failed to push image to ECR"
    exit 1
fi
