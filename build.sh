#!/usr/bin/env bash

APISIX_VERSION=3.8.0-debian
docker build --build-arg APISIX_VERSION=${APISIX_VERSION} . -t apisix-standalone