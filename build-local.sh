#!/usr/bin/env bash

APISIX_VERSION=3.8.0-debian
docker build --pull --no-cache --platform=linux/x86_64  --build-arg APISIX_VERSION=${APISIX_VERSION} . -t apisix-standalone