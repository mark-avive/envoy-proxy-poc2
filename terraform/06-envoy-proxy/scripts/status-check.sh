#!/bin/bash

# Status Check Script for Envoy Proxy Deployment
# This script checks the status of all Envoy components

set -e

echo "=== Envoy Proxy Deployment Status Check ==="
echo ""

# Check AWS Load Balancer Controller
echo "AWS Load Balancer Controller Status:"
echo "===================================="
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
echo ""

# Check Envoy Proxy Deployment
echo "Envoy Proxy Deployment Status:"
echo "==============================="
kubectl get deployments -l app=envoy-proxy
echo ""

# Check Envoy Proxy Pods
echo "Envoy Proxy Pods:"
echo "=================="
kubectl get pods -l app=envoy-proxy -o wide
echo ""

# Check Envoy Proxy Service
echo "Envoy Proxy Service:"
echo "===================="
kubectl get services -l app=envoy-proxy
echo ""

# Check Ingress and ALB
echo "Ingress and ALB Status:"
echo "======================="
kubectl get ingress envoy-proxy-ingress
echo ""

ALB_ENDPOINT=$(kubectl get ingress envoy-proxy-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -n "$ALB_ENDPOINT" ] && [ "$ALB_ENDPOINT" != "null" ]; then
    echo "ALB Endpoint: http://$ALB_ENDPOINT"
    echo ""
    
    # Test WebSocket connectivity through Envoy
    echo "Testing WebSocket connectivity through Envoy..."
    echo "==============================================="
    
    # First test basic HTTP connectivity
    echo "Testing HTTP connectivity..."
    if curl -s --connect-timeout 5 "http://$ALB_ENDPOINT" > /dev/null; then
        echo "✓ HTTP connectivity successful"
    else
        echo "✗ HTTP connectivity failed"
    fi
    
    # Test WebSocket upgrade (basic check)
    echo "Testing WebSocket upgrade capability..."
    UPGRADE_RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null \
        -H "Connection: Upgrade" \
        -H "Upgrade: websocket" \
        -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
        -H "Sec-WebSocket-Version: 13" \
        "http://$ALB_ENDPOINT" || echo "000")
    
    if [ "$UPGRADE_RESPONSE" = "101" ]; then
        echo "✓ WebSocket upgrade successful (HTTP 101)"
    elif [ "$UPGRADE_RESPONSE" = "426" ]; then
        echo "✓ Backend WebSocket server responding (HTTP 426 - Upgrade Required)"
    else
        echo "⚠ WebSocket upgrade response: HTTP $UPGRADE_RESPONSE"
    fi
else
    echo "⚠ ALB endpoint not yet available"
fi

echo ""

# Check backend server application
echo "Backend Server Application Status:"
echo "=================================="
kubectl get deployments -l app=envoy-poc-app-server
kubectl get services -l app=envoy-poc-app-server
kubectl get pods -l app=envoy-poc-app-server --field-selector=status.phase=Running | head -3
echo ""

# Check Envoy configuration
echo "Envoy Configuration:"
echo "==================="
kubectl get configmap envoy-config
echo ""

# Show Envoy admin interface accessibility
echo "Envoy Admin Interface:"
echo "======================"
ENVOY_POD=$(kubectl get pods -l app=envoy-proxy -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$ENVOY_POD" ]; then
    echo "Envoy Admin available via port-forward:"
    echo "kubectl port-forward $ENVOY_POD 9901:9901"
    echo "Then access: http://localhost:9901"
else
    echo "⚠ No Envoy pods found"
fi

echo ""
echo "=== Status Check Complete ==="
echo ""

if [ -n "$ALB_ENDPOINT" ] && [ "$ALB_ENDPOINT" != "null" ]; then
    echo "🎉 Envoy Proxy is deployed and accessible!"
    echo ""
    echo "WebSocket endpoint: ws://$ALB_ENDPOINT"
    echo "HTTP endpoint: http://$ALB_ENDPOINT"
    echo ""
    echo "Next steps:"
    echo "1. Test WebSocket connections using a WebSocket client"
    echo "2. Monitor Envoy metrics at admin interface (port 9901)"
    echo "3. Check Envoy access logs: kubectl logs -l app=envoy-proxy"
else
    echo "⚠ Deployment completed but ALB is still provisioning"
    echo "Please wait a few more minutes and check ALB status"
fi
