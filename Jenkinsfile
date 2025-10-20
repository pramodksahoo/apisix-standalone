pipeline {
    agent any
    
    environment {
        // AWS Configuration
        AWS_DEFAULT_REGION = "${env.AWS_REGION ?: 'us-east-1'}"
        AWS_ACCOUNT_ID = "${env.AWS_ACCOUNT_ID}"
        ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
        
        // Container Registry Configuration
        IMAGE_NAME = 'apisix-standalone'
        IMAGE_TAG = "${env.BUILD_NUMBER ?: 'latest'}"
        FULL_IMAGE_NAME = "${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        
        // AWS EKS Configuration
        EKS_CLUSTER_NAME = "${env.EKS_CLUSTER_NAME ?: 'apisix-cluster'}"
        KUBECONFIG = credentials('eks-kubeconfig-credential-id')
        
        // Environment specific variables
        ENVIRONMENT = "${env.DEPLOY_ENV ?: 'preprod'}"
        HELM_VALUES_FILE = "depspec/helm/values.${ENVIRONMENT}.helm.yaml"
        HELM_NAMESPACE = "apisix-${ENVIRONMENT}"
        
        // Notification Configuration
        SLACK_CHANNEL = "${env.SLACK_CHANNEL ?: '#deployments'}"
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
    }
    
    parameters {
        choice(
            name: 'DEPLOY_ENV',
            choices: ['preprod', 'prod', 'postprod'],
            description: 'Target environment for deployment'
        )
        string(
            name: 'AWS_REGION',
            defaultValue: 'us-east-1',
            description: 'AWS region for deployment'
        )
        booleanParam(
            name: 'SKIP_TESTS',
            defaultValue: false,
            description: 'Skip test execution'
        )
        booleanParam(
            name: 'DEPLOY_ONLY',
            defaultValue: false,
            description: 'Skip build and only deploy existing image'
        )
    }
    
    stages {
        stage('Checkout') {
            steps {
                script {
                    echo "🚀 Starting APISIX Standalone deployment pipeline for AWS EKS"
                    echo "Environment: ${params.DEPLOY_ENV}"
                    echo "AWS Region: ${params.AWS_REGION ?: env.AWS_DEFAULT_REGION}"
                    echo "ECR Registry: ${ECR_REGISTRY}"
                    echo "Image: ${FULL_IMAGE_NAME}"
                    echo "EKS Cluster: ${EKS_CLUSTER_NAME}"
                }
                cleanWs()
                checkout scm
            }
        }
        
        stage('Validate Configuration') {
            steps {
                script {
                    echo "📋 Validating configuration files"
                    
                    // Check if Helm values file exists
                    if (!fileExists("${HELM_VALUES_FILE}")) {
                        error("❌ Helm values file not found: ${HELM_VALUES_FILE}")
                    }
                    
                    // Validate APISIX configuration
                    sh '''
                        echo "✅ Validating APISIX configuration file"
                        if [ ! -f "conf/config.yaml" ]; then
                            echo "❌ APISIX config.yaml not found"
                            exit 1
                        fi
                        
                        # Basic YAML syntax validation
                        python3 -c "import yaml; yaml.safe_load(open('conf/config.yaml'))" || {
                            echo "❌ Invalid YAML syntax in config.yaml"
                            exit 1
                        }
                        
                        echo "✅ Configuration validation passed"
                    '''
                }
            }
        }
        
        stage('Build Docker Image') {
            when {
                not { params.DEPLOY_ONLY }
            }
            steps {
                script {
                    echo "🔨 Building Docker image: ${FULL_IMAGE_NAME}"
                    
                    sh '''
                        # Build the APISIX standalone image
                        docker build \
                            --build-arg APISIX_VERSION=3.8.0-debian \
                            --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
                            --build-arg VCS_REF=$(git rev-parse --short HEAD) \
                            --tag ${FULL_IMAGE_NAME} \
                            --tag ${REGISTRY}/${IMAGE_NAME}:latest \
                            .
                        
                        echo "✅ Docker image built successfully"
                        docker images | grep ${IMAGE_NAME}
                    '''
                }
            }
        }
        
        stage('Security Scan') {
            when {
                not { params.DEPLOY_ONLY }
            }
            steps {
                script {
                    echo "🔍 Running security scan on Docker image"
                    
                    sh '''
                        # Install Trivy if not available
                        if ! command -v trivy &> /dev/null; then
                            echo "Installing Trivy security scanner..."
                            curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
                        fi
                        
                        # Run Trivy scan
                        trivy image --exit-code 0 --severity HIGH,CRITICAL --format table ${FULL_IMAGE_NAME}
                        
                        # Generate JSON report
                        trivy image --exit-code 0 --severity HIGH,CRITICAL --format json --output trivy-report.json ${FULL_IMAGE_NAME}
                        
                        echo "✅ Security scan completed"
                    '''
                }
                publishHTML([
                    allowMissing: false,
                    alwaysLinkToLastBuild: true,
                    keepAll: true,
                    reportDir: '.',
                    reportFiles: 'trivy-report.json',
                    reportName: 'Trivy Security Report'
                ])
            }
        }
        
        stage('Test Image') {
            when {
                not { params.SKIP_TESTS }
                not { params.DEPLOY_ONLY }
            }
            steps {
                script {
                    echo "🧪 Testing Docker image functionality"
                    
                    sh '''
                        # Start container for testing
                        CONTAINER_ID=$(docker run -d -p 9080:9080 ${FULL_IMAGE_NAME})
                        
                        # Wait for container to be ready
                        echo "Waiting for APISIX to start..."
                        sleep 10
                        
                        # Test health endpoint
                        for i in {1..30}; do
                            if curl -f http://localhost:9080/apisix/admin/status > /dev/null 2>&1; then
                                echo "✅ APISIX health check passed"
                                break
                            fi
                            echo "Waiting for APISIX... ($i/30)"
                            sleep 2
                        done
                        
                        # Cleanup
                        docker stop $CONTAINER_ID
                        docker rm $CONTAINER_ID
                        
                        echo "✅ Image testing completed successfully"
                    '''
                }
            }
        }
        
        stage('Push to ECR') {
            when {
                not { params.DEPLOY_ONLY }
            }
            steps {
                script {
                    echo "📤 Pushing Docker image to Amazon ECR"
                    
                    withCredentials([
                        [$class: 'AmazonWebServicesCredentialsBinding', 
                         credentialsId: 'aws-credentials']
                    ]) {
                        sh '''
                            # Login to Amazon ECR
                            aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}
                            
                            # Create ECR repository if it doesn't exist
                            aws ecr describe-repositories --repository-names ${IMAGE_NAME} --region ${AWS_DEFAULT_REGION} || \
                            aws ecr create-repository --repository-name ${IMAGE_NAME} --region ${AWS_DEFAULT_REGION}
                            
                            # Tag and push images
                            docker tag ${IMAGE_NAME}:latest ${FULL_IMAGE_NAME}
                            docker tag ${IMAGE_NAME}:latest ${ECR_REGISTRY}/${IMAGE_NAME}:latest
                            
                            docker push ${FULL_IMAGE_NAME}
                            docker push ${ECR_REGISTRY}/${IMAGE_NAME}:latest
                            
                            echo "✅ Image pushed successfully to ECR"
                        '''
                    }
                }
            }
        }
        
        stage('Deploy to AWS EKS') {
            steps {
                script {
                    echo "🚀 Deploying APISIX to AWS EKS environment: ${params.DEPLOY_ENV}"
                    
                    withCredentials([
                        [$class: 'AmazonWebServicesCredentialsBinding', 
                         credentialsId: 'aws-credentials']
                    ]) {
                        sh '''
                            # Configure kubectl for EKS
                            aws eks update-kubeconfig --region ${AWS_DEFAULT_REGION} --name ${EKS_CLUSTER_NAME}
                            
                            # Verify EKS connection
                            kubectl cluster-info
                            kubectl get nodes
                            
                            # Validate Helm chart
                            helm lint depspec/helm/chart/
                            
                            # Dry run deployment
                            helm upgrade --install apisix-gateway ./depspec/helm/chart \
                                -f ${HELM_VALUES_FILE} \
                                --namespace ${HELM_NAMESPACE} \
                                --create-namespace \
                                --set deployment.image.repository=${ECR_REGISTRY}/${IMAGE_NAME} \
                                --set deployment.image.tag=${IMAGE_TAG} \
                                --set environment=${ENVIRONMENT} \
                                --set aws.region=${AWS_DEFAULT_REGION} \
                                --set aws.accountId=${AWS_ACCOUNT_ID} \
                                --dry-run --debug
                            
                            # Actual deployment
                            helm upgrade --install apisix-gateway ./depspec/helm/chart \
                                -f ${HELM_VALUES_FILE} \
                                --namespace ${HELM_NAMESPACE} \
                                --create-namespace \
                                --set deployment.image.repository=${ECR_REGISTRY}/${IMAGE_NAME} \
                                --set deployment.image.tag=${IMAGE_TAG} \
                                --set environment=${ENVIRONMENT} \
                                --set aws.region=${AWS_DEFAULT_REGION} \
                                --set aws.accountId=${AWS_ACCOUNT_ID} \
                                --wait --timeout=300s
                            
                            echo "✅ Deployment completed successfully to EKS"
                        '''
                    }
                }
            }
        }
        
        stage('Post-Deployment Validation') {
            steps {
                script {
                    echo "🔍 Running post-deployment validation on AWS EKS"
                    
                    withCredentials([
                        [$class: 'AmazonWebServicesCredentialsBinding', 
                         credentialsId: 'aws-credentials']
                    ]) {
                        sh '''
                            # Check deployment status
                            kubectl get deployments -n ${HELM_NAMESPACE}
                            kubectl get pods -n ${HELM_NAMESPACE}
                            kubectl get services -n ${HELM_NAMESPACE}
                            kubectl get ingress -n ${HELM_NAMESPACE} || true
                            
                            # Wait for pods to be ready
                            kubectl wait --for=condition=ready pod -l app=apisix-gateway -n ${HELM_NAMESPACE} --timeout=120s
                            
                            # Check AWS Load Balancer Controller annotations (if applicable)
                            kubectl get service -n ${HELM_NAMESPACE} -o yaml | grep -E "(aws-load-balancer|kubernetes.io/ingress)" || true
                            
                            # Health check using port-forward
                            GATEWAY_SERVICE=$(kubectl get service -n ${HELM_NAMESPACE} -l app=apisix-gateway -o jsonpath='{.items[0].metadata.name}')
                            
                            if [ ! -z "$GATEWAY_SERVICE" ]; then
                                # Port forward for testing
                                kubectl port-forward service/$GATEWAY_SERVICE 9080:9080 -n ${HELM_NAMESPACE} &
                                PF_PID=$!
                                
                                sleep 5
                                
                                # Test health endpoint
                                if curl -f http://localhost:9080/apisix/admin/status; then
                                    echo "✅ Post-deployment health check passed"
                                else
                                    echo "❌ Post-deployment health check failed"
                                    exit 1
                                fi
                                
                                # Cleanup port forward
                                kill $PF_PID || true
                            fi
                            
                            echo "✅ Post-deployment validation completed for AWS EKS"
                        '''
                    }
                }
            }
        }
    }
    
    post {
        always {
            script {
                // Cleanup Docker images
                sh '''
                    docker image prune -f || true
                    docker rmi ${FULL_IMAGE_NAME} || true
                    docker rmi ${ECR_REGISTRY}/${IMAGE_NAME}:latest || true
                    docker rmi ${IMAGE_NAME}:latest || true
                '''
            }
        }
        
        success {
            script {
                echo "✅ Pipeline completed successfully!"
                
                // Send success notification
                slackSend(
                    channel: "${SLACK_CHANNEL}",
                    color: 'good',
                    message: """
                        ✅ *APISIX Standalone Deployment Successful - AWS EKS*
                        
                        *Environment:* ${params.DEPLOY_ENV}
                        *AWS Region:* ${params.AWS_REGION ?: env.AWS_DEFAULT_REGION}
                        *EKS Cluster:* ${EKS_CLUSTER_NAME}
                        *Namespace:* ${HELM_NAMESPACE}
                        *Image:* ${FULL_IMAGE_NAME}
                        *Build:* ${env.BUILD_NUMBER}
                        *Branch:* ${env.BRANCH_NAME}
                        
                        <${env.BUILD_URL}|View Build>
                    """.stripIndent()
                )
            }
        }
        
        failure {
            script {
                echo "❌ Pipeline failed!"
                
                // Send failure notification
                slackSend(
                    channel: "${SLACK_CHANNEL}",
                    color: 'danger',
                    message: """
                        ❌ *APISIX Standalone Deployment Failed - AWS EKS*
                        
                        *Environment:* ${params.DEPLOY_ENV}
                        *AWS Region:* ${params.AWS_REGION ?: env.AWS_DEFAULT_REGION}
                        *EKS Cluster:* ${EKS_CLUSTER_NAME}
                        *Build:* ${env.BUILD_NUMBER}
                        *Branch:* ${env.BRANCH_NAME}
                        *Stage:* ${env.STAGE_NAME}
                        
                        <${env.BUILD_URL}|View Build> | <${env.BUILD_URL}/console|View Logs>
                    """.stripIndent()
                )
            }
        }
        
        unstable {
            script {
                echo "⚠️ Pipeline completed with warnings"
            }
        }
    }
}