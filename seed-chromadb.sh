#!/bin/bash
# ChromaDB Seeding Script voor Azure
# Dit script seed de ChromaDB vector database met de documentatie
# uit de jw, wmo en cs-wmo directories

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           ChromaDB Seeding - Jaap Junior                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Configuration
RESOURCE_GROUP="chatbot_jaapjunior_rg"
API_CONTAINER="jaapjunior-api"

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    echo -e "${RED}✗ Not logged in to Azure${NC}"
    echo "Please run: az login"
    exit 1
fi
echo -e "${GREEN}✓ Logged in to Azure${NC}"

# Check if API container exists
if ! az containerapp show --name $API_CONTAINER --resource-group $RESOURCE_GROUP &> /dev/null; then
    echo -e "${RED}✗ API container not found${NC}"
    echo "Please run ./azure-deploy.sh first"
    exit 1
fi
echo -e "${GREEN}✓ API container found${NC}"
echo ""

echo -e "${YELLOW}→ Seeding ChromaDB vector database...${NC}"
echo -e "${BLUE}  This will index all documents from:${NC}"
echo "    • jw/bronnen (iJw 3.2 standards)"
echo "    • wmo/bronnen (WMO standards)"
echo "    • cs-wmo/bronnen (CS-WMO standards)"
echo ""

# Note: We need to check if the API has a seed command
# For now, we'll just show instructions

echo -e "${YELLOW}Note: This script requires a seed command in the API${NC}"
echo ""
echo -e "${BLUE}Option 1: Execute seed via console${NC}"
echo "  az containerapp exec \\"
echo "    --name $API_CONTAINER \\"
echo "    --resource-group $RESOURCE_GROUP \\"
echo "    --command \"/bin/sh\""
echo ""
echo "  Then run inside container:"
echo "    cd /app && bun run seed"
echo ""

echo -e "${BLUE}Option 2: Seed happens automatically${NC}"
echo "  The API seeds ChromaDB on first startup if the collection is empty."
echo "  Check the API logs to see if seeding has completed:"
echo ""
echo "  az containerapp logs show \\"
echo "    --name $API_CONTAINER \\"
echo "    --resource-group $RESOURCE_GROUP \\"
echo "    --follow"
echo ""

echo -e "${BLUE}Option 3: Use local Docker to seed Azure ChromaDB${NC}"
echo "  1. Get ChromaDB connection string from Azure"
echo "  2. Update .env with Azure ChromaDB URL"
echo "  3. Run locally: bun run seed"
echo ""

echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Seeding instructions shown above${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
