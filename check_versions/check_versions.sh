#!/bin/bash
set -e

APP=$(yq '.app' versions.yml)
DB=$(yq '.db' versions.yml)
REDIS=$(yq '.redis' versions.yml)

# 각 요구사항 추출 (패턴에 따라 grep)
APP_SPEC=$(grep '^app' requirements.txt | sed 's/^app//')
DB_SPEC=$(grep '^db' requirements.txt | sed 's/^db//')
REDIS_SPEC=$(grep '^redis' requirements.txt | sed 's/^redis//')

python3 - <<EOF
from packaging.version import Version
from packaging.specifiers import SpecifierSet

specs = {
    "app": SpecifierSet("$APP_SPEC"),
    "db": SpecifierSet("$DB_SPEC"),
    "redis": SpecifierSet("$REDIS_SPEC"),
}

versions = {
    "app": Version("$APP"),
    "db": Version("$DB"),
    "redis": Version("$REDIS"),
}

for name, ver in versions.items():
    if ver not in specs[name]:
        print(f"❌ {name} version {ver} does not meet spec {specs[name]}")
        exit(1)
    print(f"✅ {name} version {ver} meets spec {specs[name]}")
EOF
