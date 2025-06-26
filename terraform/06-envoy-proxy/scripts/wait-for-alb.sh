#!/bin/bash

# Wait for ALB to be provisioned script
# This script waits for the AWS Application Load Balancer to be ready

set -e

REGION=${1:-us-west-2}
PROFILE=${2:-avive-cfndev-k8s}
TIMEOUT=${3:-600}  # 10 minutes

echo "=== Waiting for AWS ALB to be provisioned ==="
echo "Region: $REGION"
echo "Profile: $PROFILE"
echo "Timeout: ${TIMEOUT}s"
echo ""

# Wait for ALB to be provisioned (indicated by ingress having an address)
echo "Waiting for ALB to be provisioned..."
elapsed=0
interval=15

while [ $elapsed -lt $TIMEOUT ]; do
    echo "Checking ALB status... (${elapsed}s elapsed)"
    
    # Check if ingress has an address (ALB endpoint)
    ALB_ENDPOINT=$(kubectl get ingress envoy-proxy-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    
    if [ -n "$ALB_ENDPOINT" ] && [ "$ALB_ENDPOINT" != "null" ]; then
        echo "✓ ALB is provisioned!"
        echo "ALB Endpoint: $ALB_ENDPOINT"
        
        # Wait a bit more for ALB to be fully ready
        echo "Waiting additional 60 seconds for ALB to be fully ready..."
        sleep 60
        
        # Test ALB connectivity
        echo "Testing ALB connectivity..."
        if curl -s --connect-timeout 10 "http://$ALB_ENDPOINT" > /dev/null; then
            echo "✓ ALB is responding to requests"
        else
            echo "⚠ ALB is provisioned but not yet responding (this is normal)"
        fi
        
        break
    fi
    
    sleep $interval
    elapsed=$((elapsed + interval))
done

if [ $elapsed -ge $TIMEOUT ]; then
    echo "⚠ Timeout waiting for ALB to be provisioned"
    echo "Current ingress status:"
    kubectl describe ingress envoy-proxy-ingress
    exit 1
fi

echo ""
echo "✓ ALB provisioning completed"
