#!/bin/bash
# Starts the backend + cloudflare tunnel, then AUTO-PATCHES app_config.dart with the new URL

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_CONFIG="$SCRIPT_DIR/../lib/config/app_config.dart"

# Kill any existing instances
pkill -f "node src/server.js" 2>/dev/null || true
pkill -f "cloudflared tunnel" 2>/dev/null || true
sleep 1

# Start backend
cd "$SCRIPT_DIR"
node src/server.js > /tmp/backend.log 2>&1 &
BACKEND_PID=$!
echo "✓ Backend started (PID $BACKEND_PID)"

# Wait for backend to be ready
sleep 2
curl -sf http://localhost:3000/api/health > /dev/null || { echo "ERROR: Backend failed to start. Check /tmp/backend.log"; exit 1; }
echo "✓ Backend is up at http://localhost:3000"

# Start cloudflare tunnel
rm -f /tmp/cf.log
cloudflared tunnel --url http://localhost:3000 --no-autoupdate > /tmp/cf.log 2>&1 &
CF_PID=$!
echo "  Cloudflare tunnel starting (PID $CF_PID)..."

# Wait for tunnel URL (up to 40 seconds)
URL=""
for i in $(seq 1 20); do
  URL=$(grep -o 'https://[a-z0-9\-]*\.trycloudflare\.com' /tmp/cf.log 2>/dev/null | head -1)
  if [ -n "$URL" ]; then
    break
  fi
  sleep 2
done

if [ -z "$URL" ]; then
  echo "ERROR: Tunnel URL not found. Check /tmp/cf.log"
  cat /tmp/cf.log
  exit 1
fi

# Wait for tunnel to fully register
sleep 8

# Auto-patch app_config.dart
if [ -f "$APP_CONFIG" ]; then
  sed -i '' "s|static const String apiBaseUrl = '.*';|static const String apiBaseUrl = '$URL/api';|" "$APP_CONFIG"
  echo "✓ Auto-patched app_config.dart with new URL"
else
  echo "WARNING: Could not find $APP_CONFIG"
fi

echo ""
echo "=========================================="
echo "  Tunnel URL : $URL"
echo "  API URL    : $URL/api"
echo "  app_config : UPDATED AUTOMATICALLY"
echo "=========================================="
echo ""
echo "Now press 'r' in the flutter run terminal to hot-reload."
echo "Press Ctrl+C here to stop both backend and tunnel."
echo ""

# Keep script alive
trap "kill $BACKEND_PID $CF_PID 2>/dev/null; echo 'Stopped.'" SIGINT SIGTERM
wait $CF_PID
