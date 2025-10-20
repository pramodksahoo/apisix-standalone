# APISIX Standalone Gateway - Demo Project

## Overview

This project demonstrates a **standalone APISIX gateway** deployment solution designed for production environments on **AWS EKS clusters**. The gateway operates **without etcd dependency** and **without the APISIX Dashboard**, making it lightweight, secure, and suitable for environments where external dependencies need to be minimized.

## Why Choose Standalone Mode?

### Traditional APISIX Architecture Challenges:
- **etcd Dependency**: Requires separate etcd cluster management and maintenance
- **Network Complexity**: Additional network hops and potential points of failure
- **Security Concerns**: More attack surface with external dependencies
- **Operational Overhead**: Managing multiple components (APISIX + etcd + Dashboard)
- **Resource Consumption**: Higher memory and CPU usage due to multiple services

### Standalone Mode Benefits:
- **🚀 Simplified Architecture**: Single container deployment with file-based configuration
- **🔒 Enhanced Security**: Eliminates etcd attack surface and reduces network exposure
- **⚡ Better Performance**: No network latency to external configuration store
- **💰 Cost Effective**: Lower resource requirements and infrastructure costs
- **🛡️ High Availability**: No dependency on external services for configuration
- **📦 Container Native**: Perfect for Kubernetes and containerized environments
- **🔧 Easy Management**: Configuration through ConfigMaps and Helm values
- **🎯 Production Ready**: Ideal for microservices and cloud-native architectures

## Key Features

- ✅ **Standalone Mode**: No etcd dependency required - configuration via YAML files
- ✅ **No Dashboard**: Lightweight deployment without admin UI overhead
- ✅ **Custom Plugins**: Extensible with custom plugins for specific requirements
- ✅ **Cloud Ready**: Optimized for AWS EKS, GKE, AKS deployment
- ✅ **Helm Charts**: Production-ready Helm charts for multiple environments
- ✅ **CI/CD Support**: Complete Jenkins and GitLab pipeline integration
- ✅ **SSL/TLS Ready**: Built-in certificate management support
- ✅ **Observability**: Prometheus metrics, logging, and tracing integration

## Use Cases & Scenarios

### Perfect For:
- **Microservices Architecture**: API gateway for containerized applications
- **Edge Computing**: Lightweight gateway for edge deployments
- **Development Teams**: Simple setup without infrastructure complexity
- **Production Workloads**: High-performance API gateway with minimal overhead
- **Multi-Cloud Deployments**: Consistent deployment across cloud providers
- **Security-First Organizations**: Reduced attack surface and dependencies

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Load Balancer │───►│  APISIX Gateway │───►│  Backend APIs   │
│     (ALB/NLB)   │    │   (Standalone)  │    │   (Services)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │  Config Files   │
                       │  (ConfigMaps)   │
                       └─────────────────┘
```

## Deployment Types Supported

This project is specifically designed for **AWS EKS** deployment with support for multiple environments:

### **AWS EKS Deployment**
- **Primary Platform**: Amazon Elastic Kubernetes Service (EKS)
- **Load Balancer Integration**: AWS Application Load Balancer (ALB) and Network Load Balancer (NLB)
- **Service Mesh Ready**: Compatible with AWS App Mesh and Istio
- **Monitoring**: CloudWatch integration for logs and metrics
- **Security**: IAM roles, VPC networking, and security groups

### **Container Deployment**
- **Docker Compose**: Local development and testing
- **Amazon ECR**: Container registry for image storage
- **EKS Fargate**: Serverless container execution

### **Environment Strategy**
- **PreProd**: Pre-production testing environment
- **Prod**: Production environment with high availability
- **PostProd**: Post-production validation and testing

### **CI/CD Integration**
- **Jenkins Pipeline**: Complete AWS EKS deployment automation
- **GitLab CI/CD**: Integrated DevOps platform support with AWS integration
- **AWS CodePipeline**: (Easily adaptable from existing pipelines)
- **GitHub Actions**: (Template available)

## Custom Plugins Included

This demo includes several example plugins to showcase extensibility:

- `datadome-protect` - DDoS protection and bot management
- `jwt-header-plugin` - JWT token handling and validation
- `pci-tokenization-plugin` - PCI compliance tokenization
- `hmac-auth-simple` - HMAC authentication mechanism
- `openid-connect-multi-realm` - Multi-realm OIDC support

## Prerequisites

- **Docker** (for local builds)
- **AWS EKS Cluster** (configured and accessible)
- **AWS CLI** (configured with appropriate permissions)
- **kubectl** (configured for your EKS cluster)
- **Helm 3.x** (for deployment)
- **Jenkins** or **GitLab CI** (for automated deployments)
- **Amazon ECR** (for container image storage)

## Quick Start

### 1. Local Build

Build the custom APISIX image locally:

```bash
./build-local.sh
```

This creates: `apisix-standalone:latest`

### 2. Test Standalone Mode

Run a local standalone example:

```bash
cd example/standalone
docker-compose up
```

Test the gateway:

```bash
curl -X GET 'http://localhost:9085/get' -i
```

Expected Response:
```
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
Content-Length: 10
Connection: keep-alive
Date: Mon, 20 Oct 2025 10:30:00 GMT
Server: APISIX/3.8.0

hello web1%
```

## Deployment on AWS EKS

### Environment Setup

The project supports three environments through Helm values:

- `values.preprod.helm.yaml` - Pre-production environment
- `values.prod.helm.yaml` - Production environment  
- `values.postprod.helm.yaml` - Post-production testing environment

### Manual Deployment

1. **Build and Push Image to ECR**:
```bash
# Build the image
./build.sh

# Tag for ECR
docker tag apisix-standalone:latest <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/apisix-standalone:latest

# Login to ECR and push
aws ecr get-login-password --region <REGION> | docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com
docker push <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/apisix-standalone:latest
```

2. **Deploy to EKS**:
```bash
# Pre-production deployment
helm upgrade --install apisix-gateway ./depspec/helm/chart \
  -f ./depspec/helm/values.preprod.helm.yaml \
  --namespace apisix-preprod \
  --create-namespace

# Production deployment
helm upgrade --install apisix-gateway ./depspec/helm/chart \
  -f ./depspec/helm/values.prod.helm.yaml \
  --namespace apisix-prod \
  --create-namespace

# Post-production deployment
helm upgrade --install apisix-gateway ./depspec/helm/chart \
  -f ./depspec/helm/values.postprod.helm.yaml \
  --namespace apisix-postprod \
  --create-namespace
```

## CI/CD Pipeline Support

This project provides comprehensive CI/CD support with multiple pipeline options:

### Jenkins Pipeline (Declarative)

The project includes **standard Jenkins declarative pipeline** support with separate build and deploy stages:

- **Build Stage**: 
  - Builds Docker image with proper tagging
  - Pushes to container registry (ECR/Docker Hub)
  - Performs security scanning and linting
  - Generates build artifacts

- **Deploy Stage**: 
  - Deploys to EKS using Helm charts
  - Supports multiple environments (dev/staging/prod)
  - Performs health checks and smoke tests
  - Automatic rollback on failure

**Pipeline Files**:
- `Jenkinsfile` - Complete declarative pipeline with build and deploy stages
- `jenkins/` - Supporting scripts and configuration files

### GitLab CI Pipeline

Complete GitLab CI support with multi-stage pipeline:

- **Build Stage**: Docker image build and registry push
- **Test Stage**: Unit tests, integration tests, and security scanning
- **Deploy Stage**: Automated deployment to target environments
- **Verify Stage**: Post-deployment validation and monitoring

**Pipeline File**:
- `.gitlab-ci.yml` - Complete GitLab CI/CD configuration with all stages

### Pipeline Features

- ✅ **Multi-Environment Support**: Automated dev, staging, production deployments
- ✅ **Automated Testing**: Comprehensive test suites and validation
- ✅ **Security Scanning**: Container image vulnerability scanning with Trivy
- ✅ **Quality Gates**: Code quality checks and performance validation
- ✅ **Rollback Support**: Automated rollback on deployment failures
- ✅ **Notification Integration**: Slack/Teams/Email notifications
- ✅ **Parallel Execution**: Optimized pipeline execution for faster feedback
- ✅ **Artifact Management**: Proper versioning and artifact storage

## Configuration

### Standalone Configuration

The gateway is configured for standalone mode in `conf/config.yaml`:

```yaml
deployment:
  role: traditional
  role_traditional:
    config_provider: yaml  # No etcd required
```

### SSL Configuration

Custom CA certificates are included for secure communication:

```yaml
apisix:
  ssl:
    ssl_trusted_certificate: /usr/local/apisix/conf/ca-certificates.crt
```

## Monitoring and Observability

- **Prometheus Metrics**: Built-in metrics collection
- **Logging**: Structured logging to CloudWatch
- **Health Checks**: Kubernetes readiness and liveness probes
- **Tracing**: OpenTelemetry integration support

## Security

- **No External Dependencies**: Standalone mode eliminates etcd attack surface
- **Custom SSL**: Enhanced certificate management
- **Plugin Security**: Built-in security plugins for authentication and authorization
- **Container Security**: Regular security scanning in CI/CD

## Troubleshooting

### Common Issues

1. **Pod CrashLoopBackOff**: Check configuration files and resource limits
2. **503 Service Unavailable**: Verify backend service connectivity
3. **SSL/TLS Issues**: Validate certificate configuration

### Debug Commands

```bash
# Check pod status
kubectl get pods -n apisix

# View logs
kubectl logs -f deployment/apisix-gateway -n apisix

# Check configuration
kubectl exec -it deployment/apisix-gateway -n apisix -- cat /usr/local/apisix/conf/config.yaml
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test locally using `./build-local.sh`
5. Submit a pull request

## Support

For issues and questions:
- Create an issue in the repository
- Check the [APISIX Documentation](https://apisix.apache.org/docs/apisix/getting-started/)
- Review the [APISIX Standalone Guide](https://apisix.apache.org/docs/apisix/deployment-modes/#standalone)

---

**Note**: This is a demonstration project showcasing APISIX standalone deployment patterns on AWS EKS cluster. The configuration is optimized for learning and production use on cloud platforms. Ensure proper resource allocation, security hardening, and monitoring are in place before deploying to production environments.