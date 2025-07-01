#!/bin/bash

# Update Lua ConfigMap for Envoy Proxy with Enhanced Features
# This script updates the Lua scripts in the Envoy ConfigMap following documentation best practices

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUA_SCRIPT_PATH="$SCRIPT_DIR/k8s/redis-connection-tracker.lua"
METRICS_SCRIPT_PATH="$SCRIPT_DIR/k8s/metrics-handler.lua"
TEMP_CONFIGMAP="/tmp/lua-configmap-enhanced.yaml"

echo "🔧 Generating Enhanced Lua ConfigMap..."

# Check if Lua scripts exist
if [[ ! -f "$LUA_SCRIPT_PATH" ]]; then
    echo "❌ Main Lua script not found: $LUA_SCRIPT_PATH"
    exit 1
fi

if [[ ! -f "$METRICS_SCRIPT_PATH" ]]; then
    echo "❌ Metrics script not found: $METRICS_SCRIPT_PATH"
    exit 1
fi

# Generate ConfigMap with both scripts
cat > "$TEMP_CONFIGMAP" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: envoy-lua-scripts
  namespace: default
  labels:
    app: envoy-proxy
    component: lua-scripts
    version: enhanced
data:
  redis-connection-tracker.lua: |
EOF

# Add the main Lua script with proper indentation
sed 's/^/    /' "$LUA_SCRIPT_PATH" >> "$TEMP_CONFIGMAP"

# Add the metrics handler script
cat >> "$TEMP_CONFIGMAP" << 'EOF'
  metrics-handler.lua: |
EOF

sed 's/^/    /' "$METRICS_SCRIPT_PATH" >> "$TEMP_CONFIGMAP"

echo "✅ Enhanced ConfigMap generated: $TEMP_CONFIGMAP"

echo "🚀 Applying Enhanced Lua ConfigMap..."
kubectl apply -f "$TEMP_CONFIGMAP"

if [[ $? -eq 0 ]]; then
    echo "✅ Enhanced Lua ConfigMap updated successfully!"
    echo ""
    echo "🎯 Enhanced Lua scripts are now deployed:"
    echo "   - redis-connection-tracker.lua: Per-pod connection enforcement"
    echo "   - metrics-handler.lua: Prometheus metrics endpoint"
    echo ""
    echo "📊 Metrics endpoints available:"
    echo "   - http://envoy-pod:9902/websocket/metrics (Prometheus format)"
    echo "   - http://envoy-pod:9902/websocket/health (Health check)"
    echo ""
    echo "   To update the scripts, modify the .lua files and run this script again."
else
    echo "❌ Failed to update Enhanced Lua ConfigMap"
    exit 1
fi

# Clean up
rm -f "$TEMP_CONFIGMAP"
