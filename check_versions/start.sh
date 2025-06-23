#!/bin/bash
set -e

# 버전 로딩
export APP_VERSION=$(yq '.app' versions.yml)
export DB_VERSION=$(yq '.db' versions.yml)
export REDIS_VERSION=$(yq '.redis' versions.yml)

# 검증
./check_versions.sh

# 실행
docker compose up -d