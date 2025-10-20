# APISIX Standalone Helm Chart - Template Structure Guide

## 📁 Updated Helm Chart Structure

```
depspec/helm/
├── chart/
│   ├── Chart.yaml                     # Updated with proper metadata
│   ├── values.yaml                    # Default values template
│   └── templates/
│       ├── _helpers.tpl               # ✅ NEW: Helm helper functions
│       ├── apisix-deployment.yaml     # ✅ UPDATED: Proper Helm standards
│       ├── apisix-service.yaml        # ✅ UPDATED: Service template
│       ├── apisix-configmap.yaml      # ✅ UPDATED: APISIX config
│       ├── apisix-rout-config.yaml    # ✅ UPDATED: Routes & SSL config
│       ├── ca-cert-configmap.yaml     # ✅ NEW: CA certificates
│       ├── ingress.yaml               # ✅ NEW: AWS ALB ingress
│       └── serviceaccount.yaml        # ✅ NEW: Service account
├── values.preprod.helm.yaml          # ✅ Environment-specific values
├── values.prod.helm.yaml             # ✅ Environment-specific values
└── values.postprod.helm.yaml         # ✅ Environment-specific values
```

## 🎯 Where Your Routes Are Configured

### 1. Routes in Values Files
Your routes are defined in the `routes:` section of each environment values file:

```yaml
# In values.preprod.helm.yaml
routes:
  - uris:
      - "/v2/shipping/fees/*"
    name: Digital Order Processing (DOP) Shipping Fee Endpoint routing rules
    plugins:
      proxyRewrite:
        scheme: https
        regexUri:
          - "^/v2/shipping/fees/(.*)"
          - "/dop/v2/shipping/fees/${1}"
      oidc:
        enable: true
        clientId: gateway-client
        # ... other plugin configs
    upstream:
      nodes:
        "oc-order-processor-service.preprod.demo.com:443": 1
      type: roundrobin
      scheme: https
      pass_host: pass
```

### 2. Routes Template Processing
The `apisix-rout-config.yaml` template processes your routes from values files:

```helm
routes:
{{- range .Values.routes }}
  -
    uris:
      {{- range .uris }}
      - {{ . | quote }}
      {{- end }}
    name: {{ .name }}
    plugins:
      # Plugin processing logic here
    upstream:
      # Upstream processing logic here
{{- end }}
```

## 🔧 Supported Plugin Configurations

The template supports all your custom plugins:

### 1. OIDC Authentication
```yaml
plugins:
  oidc:
    enable: true
    clientId: gateway-client
    clientSecret: "secret"
    discovery: "https://iam.preprod.demo.com/realms/core-apps/.well-known/openid-configuration"
    introspectionEndpoint: "https://iam.preprod.demo.com/..."
    realm: core-apps
```

### 2. JWT Header Plugin
```yaml
plugins:
  jwt:
    enable: true
    claims:
      - certificateId
      - tenantId
      - merchantId
```

### 3. HMAC Authentication
```yaml
plugins:
  hmac-auth-simple:
    enable: true
    secret_key: "R3p#9sKw9$Xv3!uB7zTq2LmNp@Df#8Qs"
    algorithm: hmac-sha256
    clock_skew: 300
    validate_request_body: true
```

### 4. Rate Limiting
```yaml
plugins:
  limit-req:
    rate: 10
    burst: 20
    key_type: "ip"
```

### 5. Request ID
```yaml
plugins:
  request-id:
    enable: true
    header_name: "Unique-ID"
```

## 🌐 SSL/TLS Configuration

SSL certificates are configured in the values files:

```yaml
ssl:
  - cert: |
      -----BEGIN CERTIFICATE-----
      # Your certificate content
      -----END CERTIFICATE-----
    key: |
      -----BEGIN PRIVATE KEY-----
      # Your private key content  
      -----END PRIVATE KEY-----
    snis:
      - "apisix-preprod.demo.com"
```

## 🚀 Deployment Process

### 1. Using Helm Deploy
```bash
# Deploy to preprod
helm upgrade --install apisix-preprod ./chart \
  -f values.preprod.helm.yaml \
  --namespace apisix-preprod \
  --create-namespace

# Deploy to prod
helm upgrade --install apisix-prod ./chart \
  -f values.prod.helm.yaml \
  --namespace apisix-prod \
  --create-namespace

# Deploy to postprod  
helm upgrade --install apisix-postprod ./chart \
  -f values.postprod.helm.yaml \
  --namespace apisix-postprod \
  --create-namespace
```

### 2. Verify Deployment
```bash
# Check pods
kubectl get pods -n apisix-preprod

# Check configmaps
kubectl get configmaps -n apisix-preprod

# Check routes configuration
kubectl get configmap apisix-preprod-routes -o yaml
```

## 📝 Key Benefits

### 1. Helm Standards Compliance
- Proper labels and selectors
- Helper template functions
- Resource naming conventions
- Metadata annotations

### 2. Environment Consistency
- Uniform template structure
- Environment-specific values
- Consistent plugin configurations
- Standardized SSL handling

### 3. AWS EKS Integration
- ALB ingress controller support
- ECR registry integration
- IAM service account annotations
- Security context configurations

### 4. Route Management
- All routes preserved from original config
- Plugin demonstrations maintained
- Environment-specific endpoints
- SSL/TLS support per environment

## 🔄 Adding New Routes

To add new routes, simply update the `routes:` section in your values file:

```yaml
routes:
  # ... existing routes ...
  
  # Add new route
  - uris:
      - "/new-service/*"
    name: New Service Route
    plugins:
      proxyRewrite:
        regexUri:
          - "^/new-service/(.*)"
          - "/api/${1}"
      oidc:
        enable: true
        clientId: gateway-client
        # ... other configs
    upstream:
      nodes:
        "new-service.preprod.demo.com:443": 1
      type: roundrobin
      scheme: https
      pass_host: pass
```

## 🛠️ Template Customization

### Helper Functions Available:
- `{{ include "apisix-standalone.name" . }}`
- `{{ include "apisix-standalone.fullname" . }}`
- `{{ include "apisix-standalone.labels" . }}`
- `{{ include "apisix-standalone.selectorLabels" . }}`

### Configuration Sources:
1. **Base Template**: `chart/values.yaml`
2. **Environment Overrides**: `values.{env}.helm.yaml`
3. **Runtime Values**: CI/CD pipeline variables

This structure ensures your APISIX deployment follows Helm best practices while maintaining all your plugin demonstrations and routing configurations!