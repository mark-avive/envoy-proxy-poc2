#!/bin/bash

# Simple Envoy Deployment (Without Redis)
# This deploys the basic Envoy setup without Redis-based connection tracking

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/k8s"

echo "=== Deploying Simple Envoy Proxy (No Redis) ==="

# Check if kubectl is available
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ kubectl is not configured or cluster is not accessible"
    exit 1
fi

# Create a temporary deployment file without Lua filter
TEMP_DEPLOYMENT="/tmp/envoy-simple-deployment.yaml"

cat > "$TEMP_DEPLOYMENT" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: envoy-config
  namespace: default
  labels:
    app: envoy-proxy
    component: config
data:
  envoy.yaml: |
    admin:
      address:
        socket_address:
          protocol: TCP
          address: 0.0.0.0
          port_value: 9901

    static_resources:
      listeners:
      - name: websocket_listener
        address:
          socket_address:
            protocol: TCP
            address: 0.0.0.0
            port_value: 8080
        filter_chains:
        - filters:
          - name: envoy.filters.network.http_connection_manager
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
              scheme_header_transformation:
                scheme_to_overwrite: http
              stat_prefix: websocket_proxy
              access_log:
              - name: envoy.access_loggers.stdout
                typed_config:
                  "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog
                  log_format:
                    text_format: |
                      [%START_TIME%] "%REQ(:METHOD)% %REQ(X-ENVOY-ORIGINAL-PATH?:PATH)% %PROTOCOL%" %RESPONSE_CODE% %RESPONSE_FLAGS% %BYTES_RECEIVED% %BYTES_SENT% %DURATION% %RESP(X-ENVOY-UPSTREAM-SERVICE-TIME)% "%REQ(X-FORWARDED-FOR)%" "%REQ(USER-AGENT)%" "%REQ(X-REQUEST-ID)%" "%REQ(:AUTHORITY)%" "%UPSTREAM_HOST%"
              route_config:
                name: local_route
                virtual_hosts:
                - name: websocket_service
                  domains: ["*"]
                  routes:
                  - match:
                      prefix: "/"
                      headers:
                      - name: "upgrade"
                        string_match:
                          exact: "websocket"
                    route:
                      cluster: websocket_cluster
                      timeout: 0s
                      upgrade_configs:
                      - upgrade_type: "websocket"
                  - match:
                      prefix: "/"
                    route:
                      cluster: websocket_cluster
              http_filters:
              # Simple local rate limiting only
              - name: envoy.filters.http.local_ratelimit
                typed_config:
                  "@type": type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3.LocalRateLimit
                  stat_prefix: websocket_rate_limiter
                  token_bucket:
                    max_tokens: 10
                    tokens_per_fill: 2
                    fill_interval: 1s
                  filter_enabled:
                    runtime_key: rate_limit_enabled
                    default_value:
                      numerator: 100
                      denominator: HUNDRED
                  filter_enforced:
                    runtime_key: rate_limit_enforced
                    default_value:
                      numerator: 100
                      denominator: HUNDRED
                  response_headers_to_add:
                  - append: false
                    header:
                      key: x-rate-limited
                      value: 'true'
              - name: envoy.filters.http.router
                typed_config:
                  "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router

      clusters:
      - name: websocket_cluster
        connect_timeout: 30s
        type: STRICT_DNS
        lb_policy: ROUND_ROBIN
        dns_lookup_family: V4_ONLY
        circuit_breakers:
          thresholds:
          - priority: DEFAULT
            max_connections: 8
            max_pending_requests: 10
            max_requests: 20
            max_retries: 3
        health_checks:
        - timeout: 5s
          interval: 10s
          interval_jitter: 1s
          unhealthy_threshold: 3
          healthy_threshold: 2
          tcp_health_check: {}
        load_assignment:
          cluster_name: websocket_cluster
          endpoints:
          - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: envoy-poc-app-server-service.default.svc.cluster.local
                    port_value: 8080
        typed_extension_protocol_options:
          envoy.extensions.upstreams.http.v3.HttpProtocolOptions:
            "@type": type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions
            explicit_http_config:
              http_protocol_options:
                accept_http_10: true
            upstream_http_protocol_options:
              auto_sni: true

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: envoy-proxy
  namespace: default
  labels:
    app: envoy-proxy
    component: reverse-proxy
    version: v1.0.0
spec:
  replicas: 2
  selector:
    matchLabels:
      app: envoy-proxy
  template:
    metadata:
      labels:
        app: envoy-proxy
        component: reverse-proxy
        version: v1.0.0
    spec:
      containers:
      - name: envoy
        image: envoyproxy/envoy:v1.29-latest
        ports:
        - containerPort: 8080
          name: http
          protocol: TCP
        - containerPort: 9901
          name: admin
          protocol: TCP
        volumeMounts:
        - name: envoy-config
          mountPath: /etc/envoy
          readOnly: true
        command:
        - /usr/local/bin/envoy
        args:
        - --config-path
        - /etc/envoy/envoy.yaml
        - --service-cluster
        - envoy-proxy
        - --service-node
        - envoy-proxy
        - --log-level
        - info
        resources:
          requests:
            cpu: 125m
            memory: 128Mi
          limits:
            cpu: 250m
            memory: 256Mi
        livenessProbe:
          httpGet:
            path: /ready
            port: 9901
            scheme: HTTP
          initialDelaySeconds: 30
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: 9901
            scheme: HTTP
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 3
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          runAsGroup: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
      volumes:
      - name: envoy-config
        configMap:
          name: envoy-config
      restartPolicy: Always
      terminationGracePeriodSeconds: 30

---
apiVersion: v1
kind: Service
metadata:
  name: envoy-proxy-service
  namespace: default
  labels:
    app: envoy-proxy
    component: reverse-proxy
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
    name: http
  - port: 9901
    targetPort: 9901
    protocol: TCP
    name: admin
  selector:
    app: envoy-proxy
EOF

echo "📦 Deploying Simple Envoy Proxy..."
kubectl apply -f "$TEMP_DEPLOYMENT"

echo "⏳ Waiting for deployment to be ready..."
kubectl wait --for=condition=available deployment/envoy-proxy --timeout=120s

echo ""
echo "✅ Simple Envoy Proxy deployed successfully!"
echo ""
echo "Features:"
echo "  ✓ Per-Envoy instance rate limiting (2 connections/sec per instance)"
echo "  ✓ Per-Envoy instance circuit breakers (8 connections max per instance)"
echo "  ✓ WebSocket support with upgrade handling"
echo "  ✓ Health checks to backend pods"
echo "  ✓ Access logging"
echo ""
echo "Limitations:"
echo "  ❌ No global per-pod connection limits"
echo "  ❌ No Redis-based coordination between Envoy instances"
echo "  ❌ No scaling metrics for custom scaling decisions"
echo ""
echo "Current pods:"
kubectl get pods -l app=envoy-proxy -o wide

# Clean up temp file
rm -f "$TEMP_DEPLOYMENT"

echo ""
echo "🎯 To upgrade to enhanced Redis-based setup:"
echo "   ./deploy-enhanced.sh"
