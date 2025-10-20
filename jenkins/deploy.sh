#!/bin/bash

# Jenkins Helper Script - Deploy APISIX to Kubernetes
# This script is called by the Jenkins pipeline to deploy using Helm

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT="${DEPLOY_ENV:-preprod}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-apisix-cluster}"
AWS_REGION="${AWS_REGION:-us-east-1}"
NAMESPACE="apisix-${ENVIRONMENT}"
RELEASE_NAME="apisix-gateway"
HELM_CHART_PATH="$PROJECT_ROOT/depspec/helm/chart"
VALUES_FILE="$PROJECT_ROOT/depspec/helm/values.$ENVIRONMENT.helm.yaml"

echo "🚀 Deploying APISIX to AWS EKS"
echo "Environment: $ENVIRONMENT"
echo "EKS Cluster: $EKS_CLUSTER_NAME"
echo "AWS Region: $AWS_REGION"
echo "Namespace: $NAMESPACE"
echo "Release: $RELEASE_NAME"
echo "Chart Path: $HELM_CHART_PATH"
echo "Values File: $VALUES_FILE"

# Load image information
if [ -f "$PROJECT_ROOT/image-info.env" ]; then
    source "$PROJECT_ROOT/image-info.env"
    echo "Loaded image info: $FULL_IMAGE_NAME"
    echo "ECR Registry: $ECR_REGISTRY"
    echo "AWS Region: $AWS_REGION"
else
    echo "❌ image-info.env not found. Make sure build stage completed successfully."
    exit 1
fi

# Validate prerequisites
if [ ! -f "$VALUES_FILE" ]; then
    echo "❌ Values file not found: $VALUES_FILE"
    echo "Available values files:"
    ls -la "$PROJECT_ROOT/depspec/helm/values."*.yaml || true
    exit 1
fi

if [ ! -d "$HELM_CHART_PATH" ]; then
    echo "❌ Helm chart not found: $HELM_CHART_PATH"
    exit 1
fi

# Configure kubectl for EKS
echo "📋 Configuring kubectl for AWS EKS..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME"

# Verify EKS connection
echo "🔍 Verifying EKS connection..."
kubectl cluster-info
kubectl get nodes

# Validate Helm chart
echo "📋 Validating Helm chart..."
helm lint "$HELM_CHART_PATH"

# Dry run deployment
echo "🧪 Running dry-run deployment..."
helm upgrade --install "$RELEASE_NAME" "$HELM_CHART_PATH" \
    -f "$VALUES_FILE" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --set "image.repository=$ECR_REGISTRY/$IMAGE_NAME" \
    --set "image.tag=$IMAGE_TAG" \
    --set "environment=$ENVIRONMENT" \
    --set "aws.region=$AWS_REGION" \
    --set "aws.accountId=$AWS_ACCOUNT_ID" \
    --dry-run --debug

# Actual deployment
echo "🚀 Deploying to AWS EKS..."
helm upgrade --install "$RELEASE_NAME" "$HELM_CHART_PATH" \
    -f "$VALUES_FILE" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --set "image.repository=$ECR_REGISTRY/$IMAGE_NAME" \
    --set "image.tag=$IMAGE_TAG" \
    --set "environment=$ENVIRONMENT" \
    --set "aws.region=$AWS_REGION" \
    --set "aws.accountId=$AWS_ACCOUNT_ID" \
    --wait --timeout=300s

echo "✅ Deployment completed successfully on AWS EKS"

# Post-deployment validation
echo "🔍 Validating deployment on AWS EKS..."
kubectl get deployments -n "$NAMESPACE"
kubectl get pods -n "$NAMESPACE"
kubectl get services -n "$NAMESPACE"
kubectl get ingress -n "$NAMESPACE" || true

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=apisix-gateway -n "$NAMESPACE" --timeout=120s

echo "✅ All pods are ready on AWS EKS"

# Save deployment info
cat > deployment-info.env << EOF
DEPLOYMENT_ENVIRONMENT=$ENVIRONMENT
DEPLOYMENT_NAMESPACE=$NAMESPACE
DEPLOYMENT_RELEASE=$RELEASE_NAME
DEPLOYED_IMAGE=$FULL_IMAGE_NAME
EKS_CLUSTER_NAME=$EKS_CLUSTER_NAME
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
DEPLOYMENT_TIME=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
EOF

echo "✅ Deployment information saved to deployment-info.env"