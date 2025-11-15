#!/bin/bash

# Azure Setup Validator Agent
# Controleert alle Azure resources en configuratie

set -e

echo "=== Azure Setup Validation Agent ==="
echo ""

RG="chatbot_jaapjunior_rg"
REGISTRY="jaapjuniorregistry"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

fail_count=0
warn_count=0
pass_count=0

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((pass_count++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((fail_count++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((warn_count++))
}

echo "1. Checking Azure Container Registry..."
if az acr show --name "$REGISTRY" --query "name" -o tsv &>/dev/null; then
    check_pass "Container Registry exists"

    # Check if we can list images
    if az acr repository list --name "$REGISTRY" -o tsv &>/dev/null; then
        check_pass "Can access registry images"

        # Check for required images
        if az acr repository show --name "$REGISTRY" --image jaapjunior-api:v1.0.3 &>/dev/null; then
            check_pass "Image jaapjunior-api:v1.0.3 exists"
        else
            check_warn "Image jaapjunior-api:v1.0.3 not found"
        fi
    else
        check_fail "Cannot access registry images"
    fi
else
    check_fail "Container Registry not found"
fi

echo ""
echo "2. Checking Container Apps..."

# Check ChromaDB
echo "  ChromaDB:"
CHROMA_STATUS=$(az containerapp show --name jaapjunior-chromadb --resource-group "$RG" --query 'properties.runningStatus' -o tsv 2>/dev/null || echo "NOT_FOUND")
if [ "$CHROMA_STATUS" == "Running" ]; then
    check_pass "ChromaDB is Running"

    # Check revision
    CHROMA_REV=$(az containerapp show --name jaapjunior-chromadb --resource-group "$RG" --query 'properties.latestRevisionName' -o tsv)
    echo "    Latest revision: $CHROMA_REV"

    # Check replicas
    CHROMA_REPLICAS=$(az containerapp revision show --name jaapjunior-chromadb --resource-group "$RG" --revision "$CHROMA_REV" --query 'properties.replicas' -o tsv 2>/dev/null || echo "0")
    if [ "$CHROMA_REPLICAS" -gt 0 ]; then
        check_pass "ChromaDB has $CHROMA_REPLICAS replica(s)"
    else
        check_fail "ChromaDB has no active replicas"
    fi
elif [ "$CHROMA_STATUS" == "NOT_FOUND" ]; then
    check_fail "ChromaDB not found"
else
    check_fail "ChromaDB status: $CHROMA_STATUS"
fi

echo ""
echo "  API:"
API_STATUS=$(az containerapp show --name jaapjunior-api --resource-group "$RG" --query 'properties.runningStatus' -o tsv 2>/dev/null || echo "NOT_FOUND")
if [ "$API_STATUS" == "Running" ]; then
    check_pass "API is Running"

    # Check image
    API_IMAGE=$(az containerapp show --name jaapjunior-api --resource-group "$RG" --query 'properties.template.containers[0].image' -o tsv)
    echo "    Current image: $API_IMAGE"

    # Check revision
    API_REV=$(az containerapp show --name jaapjunior-api --resource-group "$RG" --query 'properties.latestRevisionName' -o tsv)
    echo "    Latest revision: $API_REV"

    # Check replicas
    API_REPLICAS=$(az containerapp revision show --name jaapjunior-api --resource-group "$RG" --revision "$API_REV" --query 'properties.replicas' -o tsv 2>/dev/null || echo "0")
    if [ "$API_REPLICAS" -gt 0 ]; then
        check_pass "API has $API_REPLICAS replica(s)"
    else
        check_fail "API has no active replicas"
    fi
elif [ "$API_STATUS" == "NOT_FOUND" ]; then
    check_fail "API not found"
else
    check_fail "API status: $API_STATUS"
fi

echo ""
echo "  Frontend:"
FRONTEND_STATUS=$(az containerapp show --name jaapjunior --resource-group "$RG" --query 'properties.runningStatus' -o tsv 2>/dev/null || echo "NOT_FOUND")
if [ "$FRONTEND_STATUS" == "Running" ]; then
    check_pass "Frontend is Running"

    # Check FQDN
    FRONTEND_FQDN=$(az containerapp show --name jaapjunior --resource-group "$RG" --query 'properties.configuration.ingress.fqdn' -o tsv)
    echo "    FQDN: https://$FRONTEND_FQDN"
elif [ "$FRONTEND_STATUS" == "NOT_FOUND" ]; then
    check_fail "Frontend not found"
else
    check_fail "Frontend status: $FRONTEND_STATUS"
fi

echo ""
echo "3. Checking Environment Variables..."

# Check API env vars
echo "  API Environment Variables:"
ENV_VARS=$(az containerapp show --name jaapjunior-api --resource-group "$RG" --query 'properties.template.containers[0].env[].name' -o tsv 2>/dev/null || echo "")

required_env_vars=("NODE_ENV" "PORT" "CHROMA_URI")
for var in "${required_env_vars[@]}"; do
    if echo "$ENV_VARS" | grep -q "^${var}$"; then
        check_pass "$var is set"
    else
        check_fail "$var is NOT set"
    fi
done

# Get CHROMA_URI value
CHROMA_URI=$(az containerapp show --name jaapjunior-api --resource-group "$RG" --query "properties.template.containers[0].env[?name=='CHROMA_URI'].value" -o tsv 2>/dev/null || echo "")
if [ -n "$CHROMA_URI" ]; then
    echo "    CHROMA_URI: $CHROMA_URI"
    if [[ "$CHROMA_URI" == *":8000"* ]]; then
        check_warn "CHROMA_URI contains port :8000 (may not be needed for internal URL)"
    fi
fi

echo ""
echo "4. Checking Secrets..."
SECRETS=$(az containerapp secret list --name jaapjunior-api --resource-group "$RG" --query '[].name' -o tsv 2>/dev/null || echo "")

required_secrets=("openai-api-key" "anthropic-api-key" "jinaai-api-key" "openrouter-api-key" "jwt-secret")
for secret in "${required_secrets[@]}"; do
    if echo "$SECRETS" | grep -q "^${secret}$"; then
        check_pass "Secret '$secret' exists"
    else
        check_warn "Secret '$secret' not found"
    fi
done

echo ""
echo "5. Checking Internal Connectivity..."

# Check if ChromaDB internal URL is reachable from API
echo "  Testing ChromaDB connectivity..."
if [ -n "$CHROMA_URI" ]; then
    # We can't directly test from here, but we can check the logs for connection errors
    RECENT_LOGS=$(az containerapp logs show --name jaapjunior-api --resource-group "$RG" --tail 50 2>/dev/null | grep -i "chroma\|connection" | tail -5)
    if echo "$RECENT_LOGS" | grep -qi "error\|failed\|refused"; then
        check_warn "Recent logs show potential ChromaDB connection issues"
        echo "$RECENT_LOGS"
    else
        check_pass "No obvious connection errors in recent logs"
    fi
else
    check_fail "Cannot check connectivity - CHROMA_URI not set"
fi

echo ""
echo "=== Validation Summary ==="
echo -e "${GREEN}Passed: $pass_count${NC}"
echo -e "${YELLOW}Warnings: $warn_count${NC}"
echo -e "${RED}Failed: $fail_count${NC}"
echo ""

if [ $fail_count -gt 0 ]; then
    echo "❌ Validation FAILED - please fix the issues above"
    exit 1
elif [ $warn_count -gt 0 ]; then
    echo "⚠️  Validation PASSED with warnings"
    exit 0
else
    echo "✅ All checks PASSED"
    exit 0
fi
