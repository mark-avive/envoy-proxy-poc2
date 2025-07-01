#!/bin/bash

# Generate Lua ConfigMap from standalone script
# This script creates the envoy-lua-scripts ConfigMap from the standalone redis-connection-tracker.lua file

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUA_FILE="$SCRIPT_DIR/k8s/redis-connection-tracker.lua"

if [ ! -f "$LUA_FILE" ]; then
    echo "❌ Lua script file not found: $LUA_FILE"
    exit 1
fi

echo "🔧 Generating Lua ConfigMap from standalone script..."

# Create the ConfigMap
kubectl create configmap envoy-lua-scripts \
    --from-file=redis-connection-tracker.lua="$LUA_FILE" \
    --dry-run=client -o yaml > /tmp/lua-configmap.yaml

# Add labels and metadata
cat > /tmp/lua-configmap-complete.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: envoy-lua-scripts
  namespace: default
  labels:
    app: envoy-proxy
    component: lua-scripts
data:
EOF

# Add the Lua script content with proper indentation
echo "  redis-connection-tracker.lua: |" >> /tmp/lua-configmap-complete.yaml
sed 's/^/    /' "$LUA_FILE" >> /tmp/lua-configmap-complete.yaml

echo "✅ ConfigMap generated: /tmp/lua-configmap-complete.yaml"

# Apply the ConfigMap
echo "🚀 Applying Lua ConfigMap..."
kubectl apply -f /tmp/lua-configmap-complete.yaml

echo "✅ Lua ConfigMap updated successfully!"

# Clean up temp files
rm -f /tmp/lua-configmap.yaml /tmp/lua-configmap-complete.yaml

echo ""
echo "🎯 The standalone Lua script is now the single source of truth."
echo "   To update the script, modify k8s/redis-connection-tracker.lua and run this script again."
