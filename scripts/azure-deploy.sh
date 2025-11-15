#!/bin/bash

# Azure Deployment Agent
# Bouwt en deploy images naar Azure Container Apps met versie controle

set -e

if [ -z "$1" ]; then
    echo "Usage: ./azure-deploy.sh <version>"
    echo "Example: ./azure-deploy.sh v1.0.4"
    exit 1
fi

VERSION=$1
RG="chatbot_jaapjunior_rg"
REGISTRY="jaapjuniorregistry"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Azure Deployment Agent ===${NC}"
echo "Version: $VERSION"
echo ""

# Step 1: Build and push image
echo -e "${BLUE}1. Building and pushing API image...${NC}"
cd /Users/gstevens/jaapjunior/packages/api

if az acr build --registry "$REGISTRY" \
    --image "jaapjunior-api:$VERSION" \
    --file Dockerfile .; then
    echo -e "${GREEN}✓${NC} Image built and pushed successfully"
else
    echo -e "${RED}✗${NC} Failed to build/push image"
    exit 1
fi

echo ""

# Step 2: Update Container App
echo -e "${BLUE}2. Updating Container App...${NC}"
if az containerapp update \
    --name jaapjunior-api \
    --resource-group "$RG" \
    --image "$REGISTRY.azurecr.io/jaapjunior-api:$VERSION"; then
    echo -e "${GREEN}✓${NC} Container App update initiated"
else
    echo -e "${RED}✗${NC} Failed to update Container App"
    exit 1
fi

echo ""

# Step 3: Wait for deployment to be ready
echo -e "${BLUE}3. Waiting for deployment to be ready...${NC}"
echo "This may take a few minutes..."

MAX_WAIT=300  # 5 minutes
ELAPSED=0
SLEEP_INTERVAL=10

while [ $ELAPSED -lt $MAX_WAIT ]; do
    STATUS=$(az containerapp show \
        --name jaapjunior-api \
        --resource-group "$RG" \
        --query 'properties.runningStatus' \
        -o tsv 2>/dev/null || echo "UNKNOWN")

    LATEST_REV=$(az containerapp show \
        --name jaapjunior-api \
        --resource-group "$RG" \
        --query 'properties.latestRevisionName' \
        -o tsv 2>/dev/null || echo "")

    if [ "$STATUS" == "Running" ] && [ -n "$LATEST_REV" ]; then
        # Check if revision has active replicas
        REPLICAS=$(az containerapp revision show \
            --name jaapjunior-api \
            --resource-group "$RG" \
            --revision "$LATEST_REV" \
            --query 'properties.replicas' \
            -o tsv 2>/dev/null || echo "0")

        if [ "$REPLICAS" -gt 0 ]; then
            echo -e "${GREEN}✓${NC} Deployment is ready (Status: $STATUS, Replicas: $REPLICAS)"
            break
        fi
    fi

    echo "  Status: $STATUS, Waiting... (${ELAPSED}s/${MAX_WAIT}s)"
    sleep $SLEEP_INTERVAL
    ELAPSED=$((ELAPSED + SLEEP_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}✗${NC} Deployment timeout - not ready after ${MAX_WAIT}s"
    exit 1
fi

echo ""

# Step 4: Verify correct image is running
echo -e "${BLUE}4. Verifying deployed image...${NC}"
CURRENT_IMAGE=$(az containerapp show \
    --name jaapjunior-api \
    --resource-group "$RG" \
    --query 'properties.template.containers[0].image' \
    -o tsv)

echo "Current image: $CURRENT_IMAGE"

if [[ "$CURRENT_IMAGE" == *":$VERSION" ]]; then
    echo -e "${GREEN}✓${NC} Correct version is deployed"
else
    echo -e "${RED}✗${NC} Wrong version deployed (expected $VERSION)"
    exit 1
fi

echo ""

# Step 5: Check replica health
echo -e "${BLUE}5. Checking replica health...${NC}"
LATEST_REV=$(az containerapp show \
    --name jaapjunior-api \
    --resource-group "$RG" \
    --query 'properties.latestRevisionName' \
    -o tsv)

REPLICAS=$(az containerapp revision show \
    --name jaapjunior-api \
    --resource-group "$RG" \
    --revision "$LATEST_REV" \
    --query 'properties.replicas' \
    -o tsv)

HEALTH=$(az containerapp revision show \
    --name jaapjunior-api \
    --resource-group "$RG" \
    --revision "$LATEST_REV" \
    --query 'properties.healthState' \
    -o tsv)

echo "Revision: $LATEST_REV"
echo "Replicas: $REPLICAS"
echo "Health: $HEALTH"

if [ "$HEALTH" == "Healthy" ] && [ "$REPLICAS" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Replicas are healthy"
else
    echo -e "${YELLOW}⚠${NC} Health state: $HEALTH with $REPLICAS replica(s)"
fi

echo ""

# Step 6: Show recent logs for any errors
echo -e "${BLUE}6. Checking recent logs for errors...${NC}"
RECENT_LOGS=$(az containerapp logs show \
    --name jaapjunior-api \
    --resource-group "$RG" \
    --tail 20 2>/dev/null || echo "")

if echo "$RECENT_LOGS" | grep -qi "error\|failed\|exception"; then
    echo -e "${YELLOW}⚠${NC} Recent logs contain errors:"
    echo "$RECENT_LOGS" | grep -i "error\|failed\|exception" | tail -5
else
    echo -e "${GREEN}✓${NC} No obvious errors in recent logs"
fi

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo "Version $VERSION is now running on jaapjunior-api"
echo ""
echo "Next step: Run test agent to verify functionality"
echo "  ./scripts/azure-test.sh"
