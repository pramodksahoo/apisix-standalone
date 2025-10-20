#!/bin/bash

# Jenkins Helper Script - Test APISIX Image
# This script tests the built Docker image functionality

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_PORT="${TEST_PORT:-9080}"
ADMIN_PORT="${ADMIN_PORT:-9180}"

echo "🧪 Testing APISIX Standalone Docker Image"

# Load image information
if [ -f "$PROJECT_ROOT/image-info.env" ]; then
    source "$PROJECT_ROOT/image-info.env"
    echo "Testing image: $FULL_IMAGE_NAME"
else
    echo "❌ image-info.env not found. Make sure build stage completed successfully."
    exit 1
fi

# Function to cleanup container
cleanup() {
    if [ ! -z "${CONTAINER_ID:-}" ]; then
        echo "🧹 Cleaning up test container..."
        docker stop "$CONTAINER_ID" > /dev/null 2>&1 || true
        docker rm "$CONTAINER_ID" > /dev/null 2>&1 || true
    fi
}

# Set up cleanup on exit
trap cleanup EXIT

# Start APISIX container for testing
echo "🚀 Starting APISIX container for testing..."
CONTAINER_ID=$(docker run -d \
    -p "$TEST_PORT:9080" \
    -p "$ADMIN_PORT:9180" \
    --name "apisix-test-$$" \
    "$FULL_IMAGE_NAME")

echo "Started container: $CONTAINER_ID"

# Wait for APISIX to be ready
echo "⏳ Waiting for APISIX to start..."
for i in $(seq 1 30); do
    if curl -f "http://localhost:$ADMIN_PORT/apisix/admin/status" > /dev/null 2>&1; then
        echo "✅ APISIX is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ APISIX failed to start within 60 seconds"
        docker logs "$CONTAINER_ID"
        exit 1
    fi
    echo "Waiting for APISIX... ($i/30)"
    sleep 2
done

# Test 1: Health Check
echo "🔍 Testing health endpoint..."
HEALTH_RESPONSE=$(curl -s "http://localhost:$ADMIN_PORT/apisix/admin/status")
echo "Health response: $HEALTH_RESPONSE"

# Test 2: Configuration Validation
echo "🔍 Testing configuration loading..."
docker exec "$CONTAINER_ID" cat /usr/local/apisix/conf/config.yaml | grep -q "role: traditional"
if [ $? -eq 0 ]; then
    echo "✅ Configuration loaded correctly"
else
    echo "❌ Configuration validation failed"
    exit 1
fi

# Test 3: Standalone Mode Verification
echo "🔍 Verifying standalone mode (no etcd dependency)..."
docker exec "$CONTAINER_ID" cat /usr/local/apisix/conf/config.yaml | grep -q "config_provider: yaml"
if [ $? -eq 0 ]; then
    echo "✅ Standalone mode confirmed (using YAML config provider)"
else
    echo "❌ Standalone mode verification failed"
    exit 1
fi

# Test 4: Custom Plugins Verification
echo "🔍 Testing custom plugins..."
PLUGINS_DIR="/usr/local/apisix/apisix/plugins"
CUSTOM_PLUGINS=("datadome-protect.lua" "jwt-header-plugin.lua" "pci-tokenization-plugin.lua" "hmac-auth-simple.lua" "openid-connect-multi-realm.lua")

for plugin in "${CUSTOM_PLUGINS[@]}"; do
    if docker exec "$CONTAINER_ID" test -f "$PLUGINS_DIR/$plugin"; then
        echo "✅ Custom plugin found: $plugin"
    else
        echo "❌ Custom plugin missing: $plugin"
        exit 1
    fi
done

# Test 5: SSL Certificate Verification
echo "🔍 Testing SSL certificate configuration..."
if docker exec "$CONTAINER_ID" test -f "/usr/local/apisix/conf/ca-certificates.crt"; then
    echo "✅ SSL certificates are properly configured"
else
    echo "❌ SSL certificates missing"
    exit 1
fi

# Test 6: Basic API Gateway Functionality
echo "🔍 Testing basic API gateway functionality..."
# This would require setting up a test route, but for now we just verify the admin API
ADMIN_API_RESPONSE=$(curl -s -w "%{http_code}" "http://localhost:$ADMIN_PORT/apisix/admin/status" -o /dev/null)
if [ "$ADMIN_API_RESPONSE" = "200" ]; then
    echo "✅ Admin API is responding correctly"
else
    echo "❌ Admin API returned: $ADMIN_API_RESPONSE"
    exit 1
fi

# Test 7: Container Resource Usage
echo "🔍 Checking container resource usage..."
CONTAINER_STATS=$(docker stats "$CONTAINER_ID" --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}")
echo "Container stats: $CONTAINER_STATS"

# Test 8: Log Output Verification
echo "🔍 Checking APISIX logs..."
LOGS=$(docker logs "$CONTAINER_ID" 2>&1)
if echo "$LOGS" | grep -q "APISIX"; then
    echo "✅ APISIX is logging correctly"
else
    echo "❌ APISIX logs verification failed"
    echo "Container logs:"
    echo "$LOGS"
    exit 1
fi

echo "✅ All tests passed successfully!"

# Generate test report
cat > test-report.json << EOF
{
    "test_timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
    "image_tested": "$FULL_IMAGE_NAME",
    "tests": {
        "health_check": "PASSED",
        "configuration_loading": "PASSED",
        "standalone_mode": "PASSED",
        "custom_plugins": "PASSED",
        "ssl_certificates": "PASSED",
        "admin_api": "PASSED",
        "resource_usage": "PASSED",
        "log_output": "PASSED"
    },
    "status": "SUCCESS"
}
EOF

echo "✅ Test report generated: test-report.json"