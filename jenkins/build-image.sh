#!/bin/bash

# Jenkins Helper Script - Build APISIX Standalone Image
# This script is called by the Jenkins pipeline to build the Docker image

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
IMAGE_NAME="${IMAGE_NAME:-apisix-standalone}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
BUILD_NUMBER="${BUILD_NUMBER:-latest}"

echo "🔨 Building APISIX Standalone Docker Image for AWS ECR"
echo "Project Root: $PROJECT_ROOT"
echo "Image Name: $IMAGE_NAME"
echo "ECR Registry: $ECR_REGISTRY"
echo "AWS Region: $AWS_REGION"
echo "Build Number: $BUILD_NUMBER"

cd "$PROJECT_ROOT"

# Build the image
docker build \
    --build-arg APISIX_VERSION=3.8.0-debian \
    --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --build-arg VCS_REF="$(git rev-parse --short HEAD)" \
    --build-arg BUILD_NUMBER="$BUILD_NUMBER" \
    --tag "$ECR_REGISTRY/$IMAGE_NAME:$BUILD_NUMBER" \
    --tag "$ECR_REGISTRY/$IMAGE_NAME:latest" \
    --tag "$IMAGE_NAME:latest" \
    .

echo "✅ Docker image built successfully for AWS ECR"
echo "Image: $ECR_REGISTRY/$IMAGE_NAME:$BUILD_NUMBER"

# Optional: Save image info for next stages
cat > image-info.env << EOF
FULL_IMAGE_NAME=$ECR_REGISTRY/$IMAGE_NAME:$BUILD_NUMBER
IMAGE_LATEST=$ECR_REGISTRY/$IMAGE_NAME:latest
ECR_REGISTRY=$ECR_REGISTRY
IMAGE_NAME=$IMAGE_NAME
IMAGE_TAG=$BUILD_NUMBER
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
EOF

echo "✅ Image information saved to image-info.env"