#!/bin/sh
set -e

# Default API URL - fallback naar Railway voor backwards compatibility
API_BACKEND_URL=${API_BACKEND_URL:-"https://api-production-1f41.up.railway.app"}

# Extract hostname from URL for Host header
# Remove protocol (http:// or https://), port number, and path
API_HOSTNAME=$(echo "$API_BACKEND_URL" | sed -e 's|^https\?://||' -e 's|:[0-9]*||' -e 's|/.*||')

echo "════════════════════════════════════════════════════════════"
echo "  Jaap Junior Frontend - Starting"
echo "════════════════════════════════════════════════════════════"
echo "API Backend URL: $API_BACKEND_URL"
echo "API Hostname: $API_HOSTNAME"
echo ""

# Vervang placeholders in template met echte waarden
echo "→ Configuring nginx with API backend..."
sed -e "s|\${API_BACKEND_URL}|$API_BACKEND_URL|g" \
    -e "s|\${API_HOSTNAME}|$API_HOSTNAME|g" \
    /etc/nginx/templates/nginx.conf.template > /etc/nginx/conf.d/default.conf

echo "✓ Nginx configured successfully"
echo ""

# Test nginx configuratie
echo "→ Testing nginx configuration..."
nginx -t

echo ""
echo "✓ Configuration valid"
echo ""
echo "→ Starting nginx..."
echo "════════════════════════════════════════════════════════════"
echo ""

# Start nginx in foreground
exec nginx -g "daemon off;"
