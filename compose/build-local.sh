#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DOCKER_REGISTRY="digitaltwins/logistics"
VERSION="v1.0.0"

echo -e "${BLUE}BUILD LOCAL - DIGITAL TWINS${NC}"
echo

echo -e "${BLUE}[1/5] MS-AUTH-PY${NC}"
cd ../../MS-AUTH-PY
docker build -t ${DOCKER_REGISTRY}:ms-auth-py-${VERSION} .
docker tag ${DOCKER_REGISTRY}:ms-auth-py-${VERSION} ${DOCKER_REGISTRY}:ms-auth-py-latest
echo -e "${GREEN}✓ MS-AUTH-PY${NC}"

echo -e "${BLUE}[2/5] MS-GEO-PY${NC}"
cd ../MS-GEO-PY
docker build -t ${DOCKER_REGISTRY}:ms-geo-py-${VERSION} .
docker tag ${DOCKER_REGISTRY}:ms-geo-py-${VERSION} ${DOCKER_REGISTRY}:ms-geo-py-latest
echo -e "${GREEN}✓ MS-GEO-PY${NC}"

echo -e "${BLUE}[3/5] MS-USER-PY${NC}"
cd ../MS-USER-PY
docker build -t ${DOCKER_REGISTRY}:ms-user-py-${VERSION} .
docker tag ${DOCKER_REGISTRY}:ms-user-py-${VERSION} ${DOCKER_REGISTRY}:ms-user-py-latest
echo -e "${GREEN}✓ MS-USER-PY${NC}"

echo -e "${BLUE}[4/5] MS-REPORT-PY${NC}"
cd ../MS-REPORT-PY
docker build -t ${DOCKER_REGISTRY}:ms-report-py-${VERSION} .
docker tag ${DOCKER_REGISTRY}:ms-report-py-${VERSION} ${DOCKER_REGISTRY}:ms-report-py-latest
echo -e "${GREEN}✓ MS-REPORT-PY${NC}"

echo -e "${BLUE}[5/5] FRONTEND${NC}"
cd ../FR-LOG-RT
docker build -t ${DOCKER_REGISTRY}:frontend-${VERSION} .
docker tag ${DOCKER_REGISTRY}:frontend-${VERSION} ${DOCKER_REGISTRY}:frontend-latest
echo -e "${GREEN}✓ FRONTEND${NC}"

echo
echo -e "${GREEN}✓ ALL IMAGES BUILT LOCALLY${NC}"
echo
docker images | grep "${DOCKER_REGISTRY}" | head -10
echo
echo -e "${YELLOW}Next: docker-compose up -d${NC}"