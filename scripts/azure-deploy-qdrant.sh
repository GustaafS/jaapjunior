#!/bin/bash

# Azure Deployment Script voor Jaap Junior met Qdrant
# Versie: 1.0
# Datum: November 2025

set -e  # Exit bij eerste error

# Kleuren voor output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuratie
RG="chatbot_jaapjunior_rg"
REGISTRY="jaapjuniorregistry"
API_APP="jaapjunior-api"
QDRANT_APP="jaapjunior-qdrant"
FRONTEND_APP="jaapjunior"

# Functies
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Stap 1: Verificatie van prerequisites
log_info "Stap 1: Verificatie van prerequisites..."

# Check Azure CLI
if ! command -v az &> /dev/null; then
    log_error "Azure CLI is niet geïnstalleerd"
    exit 1
fi

# Check login status
if ! az account show &> /dev/null; then
    log_error "Niet ingelogd in Azure. Run: az login"
    exit 1
fi

log_success "Prerequisites OK"
echo ""

# Stap 2: Check Qdrant status
log_info "Stap 2: Verificatie Qdrant status..."

QDRANT_STATUS=$(az containerapp show \
    --name "$QDRANT_APP" \
    --resource-group "$RG" \
    --query 'properties.runningStatus' \
    -o tsv 2>/dev/null || echo "NOT_FOUND")

if [ "$QDRANT_STATUS" != "Running" ]; then
    log_warning "Qdrant status: $QDRANT_STATUS"
else
    log_success "Qdrant status: Running"
fi

# Check Qdrant ingress
QDRANT_INGRESS=$(az containerapp ingress show \
    --name "$QDRANT_APP" \
    --resource-group "$RG" \
    --query 'targetPort' \
    -o tsv 2>/dev/null || echo "NOT_CONFIGURED")

if [ "$QDRANT_INGRESS" != "6333" ]; then
    log_warning "Qdrant ingress niet geconfigureerd"
    log_info "Enabling Qdrant ingress..."

    az containerapp ingress enable \
        --name "$QDRANT_APP" \
        --resource-group "$RG" \
        --type internal \
        --target-port 6333 \
        --transport http \
        --output none

    log_success "Qdrant ingress enabled"
else
    log_success "Qdrant ingress OK (port 6333)"
fi

echo ""

# Stap 3: Build en push API image
log_info "Stap 3: Build en push API image..."
log_info "Dit duurt ongeveer 3-5 minuten..."

# Get current directory (should be project root)
PROJECT_ROOT=$(pwd)

# Start build
BUILD_START=$(date +%s)
az acr build \
    --registry "$REGISTRY" \
    --image "${API_APP}:latest" \
    --file packages/api/Dockerfile \
    --platform linux/amd64 \
    . || {
        log_error "Build failed"
        exit 1
    }

BUILD_END=$(date +%s)
BUILD_DURATION=$((BUILD_END - BUILD_START))

log_success "Build completed in ${BUILD_DURATION}s"
echo ""

# Stap 4: Deploy nieuwe API image
log_info "Stap 4: Deploy nieuwe API image naar Azure..."

az containerapp update \
    --name "$API_APP" \
    --resource-group "$RG" \
    --image "${REGISTRY}.azurecr.io/${API_APP}:latest" \
    --output none || {
        log_error "Deployment failed"
        exit 1
    }

# Get current revision
CURRENT_REVISION=$(az containerapp show \
    --name "$API_APP" \
    --resource-group "$RG" \
    --query 'properties.latestRevisionName' \
    -o tsv)

log_success "Deployed revision: $CURRENT_REVISION"
echo ""

# Stap 5: Wait for deployment to be ready
log_info "Stap 5: Wachten op deployment..."

MAX_RETRIES=30
RETRY_INTERVAL=5
RETRIES=0

while [ $RETRIES -lt $MAX_RETRIES ]; do
    REVISION_STATUS=$(az containerapp revision show \
        --name "$API_APP" \
        --resource-group "$RG" \
        --revision "$CURRENT_REVISION" \
        --query 'properties.runningState' \
        -o tsv 2>/dev/null || echo "UNKNOWN")

    if [ "$REVISION_STATUS" == "Running" ]; then
        log_success "Revision is running"
        break
    fi

    RETRIES=$((RETRIES + 1))
    log_info "Status: $REVISION_STATUS - Retry $RETRIES/$MAX_RETRIES..."
    sleep $RETRY_INTERVAL
done

if [ $RETRIES -eq $MAX_RETRIES ]; then
    log_error "Deployment timeout - revision did not start"
    exit 1
fi

echo ""

# Stap 6: Restart API om Qdrant connection te herstellen
log_info "Stap 6: Restart API container..."

az containerapp revision restart \
    --name "$API_APP" \
    --resource-group "$RG" \
    --revision "$CURRENT_REVISION" \
    --output none || {
        log_warning "Restart failed, but deployment may still work"
    }

log_success "API restarted"
echo ""

# Stap 7: Verificatie
log_info "Stap 7: Verificatie van deployment..."

# Wait a bit for API to start
sleep 10

# Check API logs for errors
log_info "Checking API logs for errors..."
RECENT_ERRORS=$(az containerapp logs show \
    --name "$API_APP" \
    --resource-group "$RG" \
    --tail 30 2>&1 | grep -i "error\|connection.*refused" | wc -l || echo "0")

if [ "$RECENT_ERRORS" -gt "0" ]; then
    log_warning "Found $RECENT_ERRORS error(s) in recent logs"
    log_info "Check logs with: az containerapp logs show --name $API_APP --resource-group $RG --follow"
else
    log_success "No errors found in recent logs"
fi

echo ""

# Stap 8: Display URLs
log_success "=== Deployment Compleet ==="
echo ""
log_info "Application URLs:"

FRONTEND_URL=$(az containerapp show \
    --name "$FRONTEND_APP" \
    --resource-group "$RG" \
    --query 'properties.configuration.ingress.fqdn' \
    -o tsv)

API_URL=$(az containerapp show \
    --name "$API_APP" \
    --resource-group "$RG" \
    --query 'properties.configuration.ingress.fqdn' \
    -o tsv)

QDRANT_URL=$(az containerapp show \
    --name "$QDRANT_APP" \
    --resource-group "$RG" \
    --query 'properties.configuration.ingress.fqdn' \
    -o tsv)

echo ""
echo "  Frontend:  https://$FRONTEND_URL"
echo "  API:       http://$API_URL:3000"
echo "  Qdrant:    http://$QDRANT_URL:6333"
echo ""

log_info "Test de applicatie:"
echo "  open https://$FRONTEND_URL"
echo ""

log_info "Monitor logs:"
echo "  az containerapp logs show --name $API_APP --resource-group $RG --follow"
echo ""

log_success "Deployment succesvol afgerond!"
