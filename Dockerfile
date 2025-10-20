# APISIX Standalone Gateway Dockerfile
# This Dockerfile builds a custom APISIX image for standalone deployment
# without etcd dependency, optimized for AWS EKS

# Build Arguments
ARG APISIX_VERSION=3.8.0-debian
ARG BUILD_DATE
ARG VCS_REF
ARG BUILD_NUMBER

# Base Image - Apache APISIX
FROM apache/apisix:${APISIX_VERSION}

# Labels for better image metadata
LABEL maintainer="APISIX Standalone Demo" \
      description="APISIX API Gateway in Standalone Mode" \
      version="${APISIX_VERSION}" \
      build.date="${BUILD_DATE}" \
      build.vcs-ref="${VCS_REF}" \
      build.number="${BUILD_NUMBER}"

# Switch to root for installation steps
USER root

# Install additional tools for debugging and monitoring (optional)
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Copy custom CA certificates for SSL/TLS trust
COPY --chown=apisix:apisix ./conf/ca-certificates.crt /usr/local/apisix/conf/ca-certificates.crt

# Copy custom plugins for extended functionality
COPY --chown=apisix:apisix ./plugins/datadome-protect.lua /usr/local/apisix/apisix/plugins/datadome-protect.lua
COPY --chown=apisix:apisix ./plugins/jwt-header-plugin.lua /usr/local/apisix/apisix/plugins/jwt-header-plugin.lua
COPY --chown=apisix:apisix ./plugins/pci-tokenization-plugin.lua /usr/local/apisix/apisix/plugins/pci-tokenization-plugin.lua
COPY --chown=apisix:apisix ./plugins/hmac-auth-simple.lua /usr/local/apisix/apisix/plugins/hmac-auth-simple.lua
COPY --chown=apisix:apisix ./plugins/openid-connect-multi-realm.lua /usr/local/apisix/apisix/plugins/openid-connect-multi-realm.lua

# Copy APISIX standalone configuration
COPY --chown=apisix:apisix ./conf/config.yaml /usr/local/apisix/conf/config.yaml

# Set proper permissions for configuration files
RUN chmod 644 /usr/local/apisix/conf/config.yaml \
    && chmod 644 /usr/local/apisix/conf/ca-certificates.crt \
    && chmod 644 /usr/local/apisix/apisix/plugins/*.lua

# Create directories for logs and cache with proper permissions
RUN mkdir -p /usr/local/apisix/logs \
    && mkdir -p /tmp/apisix_cores \
    && chown -R apisix:apisix /usr/local/apisix/logs \
    && chown -R apisix:apisix /tmp/apisix_cores

# Switch back to apisix user for security
USER apisix

# Health check to ensure APISIX is running properly
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:9080/apisix/admin/status || exit 1

# Expose ports
EXPOSE 9080 9443 9180

# Default command - start APISIX in foreground
CMD ["/usr/local/openresty/bin/openresty", "-p", "/usr/local/apisix", "-g", "daemon off;"]