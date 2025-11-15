#!/bin/bash
# Test script voor Railway deployment met Qdrant
# Gebruik: RAILWAY_URL="https://your-app.railway.app" ./test-railway.sh

# Check if RAILWAY_URL is set
if [ -z "$RAILWAY_URL" ]; then
  echo "❌ RAILWAY_URL niet ingesteld!"
  echo ""
  echo "Gebruik:"
  echo "  RAILWAY_URL=\"https://your-app.railway.app\" ./test-railway.sh"
  echo ""
  echo "Of stel eerst in:"
  echo "  export RAILWAY_URL=\"https://your-app.railway.app\""
  echo "  ./test-railway.sh"
  exit 1
fi

# Remove trailing slash if present
RAILWAY_URL="${RAILWAY_URL%/}"

echo "=========================================="
echo "   Railway Test (Qdrant + API)"
echo "=========================================="
echo "Testing: $RAILWAY_URL"
echo ""

# 1. Health check
echo "1. Health check..."
HEALTH=$(curl -s "$RAILWAY_URL/api/v1" --max-time 10)
if [ "$HEALTH" = "OK" ]; then
  echo "✅ API is healthy"
else
  echo "❌ API not healthy: $HEALTH"
  echo ""
  echo "Troubleshooting:"
  echo "- Check if deployment is succesvol in Railway dashboard"
  echo "- Verify service is running: railway logs"
  echo "- Check environment variables zijn correct"
  exit 1
fi
echo ""

# 2. Login
echo "2. Login..."
echo "   Gebruik je SHARED_PASSWORD uit Railway environment variables"
echo "   (Niet de default 'test123' tenzij je dat expliciet hebt ingesteld)"
echo ""
read -sp "   Voer SHARED_PASSWORD in: " PASSWORD
echo ""

TOKEN=$(curl -s -X POST "$RAILWAY_URL/api/v1/auth" \
  -H "Content-Type: application/json" \
  -d "{\"password\": \"$PASSWORD\"}" \
  --max-time 10 | jq -r '.jwt' 2>/dev/null)

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "❌ Login failed"
  echo ""
  echo "Troubleshooting:"
  echo "- Verify SHARED_PASSWORD in Railway environment variables"
  echo "- Check API logs: railway logs"
  exit 1
fi
echo "✅ Login successful"
echo ""

# 3. Test cs-wmo agent
echo "3. Test cs-wmo agent..."
echo "   Vraag: 'Wat zijn contractstandaarden?'"
echo "   (Eerste keer kan 30-60s duren vanwege indexing)"
START=$(date +%s)

RESPONSE=$(curl -s -X POST "$RAILWAY_URL/api/v1/question" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"q": "Wat zijn contractstandaarden?", "agent": "cs-wmo"}' \
  --max-time 90 2>&1)

END=$(date +%s)
DURATION=$((END - START))

echo "   Response tijd: ${DURATION}s"

if echo "$RESPONSE" | grep -q "stream timeout\|timed out"; then
  echo "❌ Request timed out after ${DURATION}s"
  echo ""
  echo "Dit kan gebeuren als:"
  echo "- Documents worden geïndexeerd (eerste keer duurt lang)"
  echo "- Railway free tier heeft memory/CPU limits"
  echo ""
  echo "Probeer nogmaals, tweede keer is sneller!"
  exit 1
elif echo "$RESPONSE" | grep -q '"error"'; then
  echo "❌ Error in response:"
  echo "$RESPONSE" | jq -r '.error' 2>/dev/null || echo "$RESPONSE"
  echo ""
  echo "Check Railway logs: railway logs"
  exit 1
elif echo "$RESPONSE" | grep -q '"response"'; then
  echo "✅ Agent werkt correct met Qdrant"
  echo ""
  echo "Antwoord (eerste 200 chars):"
  echo "$RESPONSE" | jq -r '.response' 2>/dev/null | head -c 200
  echo "..."
else
  echo "❌ Unexpected response format"
  echo "$RESPONSE" | head -50
  exit 1
fi

echo ""
echo "=========================================="
echo "   ✅ Alle tests geslaagd!"
echo "=========================================="
echo ""
echo "Railway deployment werkt correct!"
echo "URL: $RAILWAY_URL"
echo ""
echo "Volgende stappen:"
echo "1. Test met verschillende vragen"
echo "2. Monitor performance in Railway dashboard"
echo "3. Check costs in Railway billing"
