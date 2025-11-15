#!/bin/bash
# Test script voor lokale Docker setup met Qdrant
# Gebruik: ./test-local-docker.sh

URL="http://localhost:3001"

echo "=========================================="
echo "   Lokale Docker Test (Qdrant + API)"
echo "=========================================="
echo ""

# 1. Health check
echo "1. Health check..."
HEALTH=$(curl -s "$URL/api/v1")
if [ "$HEALTH" = "OK" ]; then
  echo "✅ API is healthy"
else
  echo "❌ API not healthy: $HEALTH"
  exit 1
fi
echo ""

# 2. Login
echo "2. Login..."
TOKEN=$(curl -s -X POST "$URL/api/v1/auth" \
  -H "Content-Type: application/json" \
  -d '{"password": "test123"}' | jq -r '.jwt')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "❌ Login failed"
  exit 1
fi
echo "✅ Login successful"
echo ""

# 3. Test cs-wmo agent
echo "3. Test cs-wmo agent..."
echo "   Vraag: 'Wat zijn contractstandaarden?'"
START=$(date +%s)

RESPONSE=$(curl -s -X POST "$URL/api/v1/question" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"q": "Wat zijn contractstandaarden?", "agent": "cs-wmo"}' \
  --max-time 60 2>&1)

END=$(date +%s)
DURATION=$((END - START))

echo "   Response tijd: ${DURATION}s"

if echo "$RESPONSE" | grep -q "stream timeout\|timed out"; then
  echo "❌ Request timed out after ${DURATION}s"
  exit 1
elif echo "$RESPONSE" | grep -q '"error"'; then
  echo "❌ Error in response:"
  echo "$RESPONSE" | jq -r '.error' 2>/dev/null || echo "$RESPONSE"
  exit 1
else
  # Try array format first (new format: [{"content":"..."}])
  RESPONSE_TEXT=$(echo "$RESPONSE" | jq -r '.[0].content' 2>/dev/null)

  # Fallback to direct response field (old format: {"response":"..."})
  if [ -z "$RESPONSE_TEXT" ] || [ "$RESPONSE_TEXT" = "null" ]; then
    RESPONSE_TEXT=$(echo "$RESPONSE" | jq -r '.response' 2>/dev/null)
  fi

  if [ -n "$RESPONSE_TEXT" ] && [ "$RESPONSE_TEXT" != "null" ]; then
    echo "✅ Agent werkt correct met Qdrant"
    echo ""
    echo "Antwoord (eerste 200 chars):"
    echo "$RESPONSE_TEXT" | head -c 200
    echo "..."
  else
    echo "❌ Unexpected response format"
    exit 1
  fi
fi

echo ""
echo "=========================================="
echo "   ✅ Alle tests geslaagd!"
echo "=========================================="
