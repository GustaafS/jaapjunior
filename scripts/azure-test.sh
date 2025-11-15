#!/bin/bash

# Azure End-to-End Test Agent
# Test complete flow: login, create conversation, send message

set -e

BASE_URL="https://jaapjunior.bluerock-7a3df5c8.westeurope.azurecontainerapps.io"
PASSWORD="test123"
TEST_MESSAGE="Wat is de WMO?"
AGENT="jw"
TIMEOUT=300  # 5 minutes for message response

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Azure End-to-End Test Agent ===${NC}"
echo "Base URL: $BASE_URL"
echo "Test message: $TEST_MESSAGE"
echo "Agent: $AGENT"
echo ""

# Step 1: Login
echo -e "${BLUE}1. Testing login...${NC}"
LOGIN_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "$BASE_URL/api/v1/auth" \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"$PASSWORD\"}")

HTTP_STATUS=$(echo "$LOGIN_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
BODY=$(echo "$LOGIN_RESPONSE" | sed '/HTTP_STATUS:/d')

if [ "$HTTP_STATUS" == "200" ]; then
    JWT=$(echo "$BODY" | grep -o '"jwt":"[^"]*"' | cut -d'"' -f4)
    if [ -n "$JWT" ]; then
        echo -e "${GREEN}✓${NC} Login successful"
        echo "  JWT: ${JWT:0:30}..."
    else
        echo -e "${RED}✗${NC} Login returned 200 but no JWT found"
        echo "  Response: $BODY"
        exit 1
    fi
else
    echo -e "${RED}✗${NC} Login failed with status $HTTP_STATUS"
    echo "  Response: $BODY"
    exit 1
fi

echo ""

# Step 2: Create conversation
echo -e "${BLUE}2. Creating conversation...${NC}"
CONV_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "$BASE_URL/api/v1/conversations" \
  -H "Authorization: Bearer $JWT")

HTTP_STATUS=$(echo "$CONV_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
BODY=$(echo "$CONV_RESPONSE" | sed '/HTTP_STATUS:/d')

if [ "$HTTP_STATUS" == "200" ] || [ "$HTTP_STATUS" == "201" ]; then
    CONV_ID=$(echo "$BODY" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    if [ -n "$CONV_ID" ]; then
        echo -e "${GREEN}✓${NC} Conversation created"
        echo "  ID: $CONV_ID"
    else
        echo -e "${RED}✗${NC} Conversation creation returned $HTTP_STATUS but no ID found"
        echo "  Response: $BODY"
        exit 1
    fi
else
    echo -e "${RED}✗${NC} Conversation creation failed with status $HTTP_STATUS"
    echo "  Response: $BODY"
    exit 1
fi

echo ""

# Step 3: Send message
echo -e "${BLUE}3. Sending test message...${NC}"
echo "  This may take a few minutes on first run (indexing documents)"
echo ""

MSG_RESPONSE=$(curl -s --max-time $TIMEOUT -w "\nHTTP_STATUS:%{http_code}" \
  -X POST "$BASE_URL/api/v1/conversations/$CONV_ID" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d "{\"inputText\":\"$TEST_MESSAGE\",\"agent\":\"$AGENT\"}")

HTTP_STATUS=$(echo "$MSG_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
BODY=$(echo "$MSG_RESPONSE" | sed '/HTTP_STATUS:/d')

if [ "$HTTP_STATUS" == "200" ]; then
    # Check if response contains an error
    if echo "$BODY" | grep -q '"error"'; then
        ERROR_MSG=$(echo "$BODY" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
        echo -e "${RED}✗${NC} Message sent but API returned error"
        echo "  Error: $ERROR_MSG"
        echo ""
        echo "Full response:"
        echo "$BODY" | head -20
        exit 1
    else
        # Check if we got a valid response with text
        RESPONSE_TEXT=$(echo "$BODY" | grep -o '"response":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$RESPONSE_TEXT" ]; then
            echo -e "${GREEN}✓${NC} Message sent and response received"
            echo ""
            echo "Response preview:"
            echo "$RESPONSE_TEXT" | head -c 200
            echo "..."
            echo ""
            echo -e "${GREEN}=== All Tests PASSED ===${NC}"
            exit 0
        else
            echo -e "${YELLOW}⚠${NC} Message sent (200) but response format unexpected"
            echo ""
            echo "Response preview:"
            echo "$BODY" | head -20
            exit 0
        fi
    fi
elif [ "$HTTP_STATUS" == "000" ]; then
    echo -e "${RED}✗${NC} Request timeout after ${TIMEOUT}s"
    echo "  The API might be stuck or taking too long to respond"
    echo "  Check the logs with: az containerapp logs show --name jaapjunior-api --resource-group chatbot_jaapjunior_rg --tail 50"
    exit 1
else
    echo -e "${RED}✗${NC} Message failed with status $HTTP_STATUS"
    echo ""
    echo "Response:"
    echo "$BODY" | head -30
    exit 1
fi
