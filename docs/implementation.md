================================================================================
               WEBSOCKET CONNECTION MANAGEMENT WITH ENVOY PROXY ON EKS
================================================================================

FEASIBILITY: YES - HIGHLY RECOMMENDED APPROACH

ARCHITECTURE OVERVIEW
=====================

Client Pods → AWS ALB → Envoy Proxy Pods → Server Pods
                             ↓
                    Metrics & Rate Limiting

IMPLEMENTATION FLOW
===================

CONNECTION LIFECYCLE:
1. Client pods initiate WebSocket connections through AWS ALB
2. ALB forwards requests to Envoy proxy pods via Kubernetes Service  
3. Envoy proxy applies rate limiting and connection limit checks
4. If approved, Envoy establishes and maintains WebSocket connection to backend
5. Connection state tracked and metrics updated throughout lifecycle

DECISION FLOW FOR NEW CONNECTIONS:
┌─────────────────────────┐
│ Incoming WebSocket      │
│ Request                 │
└─────────┬───────────────┘
          ↓
┌─────────────────────────┐
│ Global Rate Limit       │
│ Check                   │
└─────────┬───────────────┘
          ↓
┌─────────────────────────┐
│ Per-Pod Connection      │
│ Limit Check             │
└─────────┬───────────────┘
          ↓
┌─────────────────────────┐
│ Circuit Breaker         │
│ Status Check            │
└─────────┬───────────────┘
          ↓
┌─────────────────────────┐
│ Allow/Reject &          │
│ Update Metrics          │
└─────────────────────────┘

CORE COMPONENTS & EXTENSIONS
============================

1. CONNECTION MANAGEMENT
   ├── HTTP Connection Manager
   │   └── Handles WebSocket upgrade requests and connection lifecycle
   ├── Circuit Breakers  
   │   └── Cluster-level configuration for concurrent connections per pod
   └── Custom Lua Filter
       └── Fine-grained per-pod connection tracking and limits

2. RATE LIMITING STACK
   ├── Local Rate Limiter (envoy.filters.http.local_ratelimit)
   │   └── Controls new connection rate per proxy instance
   ├── Global Rate Limiter (envoy.filters.http.ratelimit)
   │   └── Optional cluster-wide limits using external service (Redis)
   └── Connection Limit Filter (envoy.filters.network.connection_limit)
       └── Network-level connection limiting

3. METRICS & OBSERVABILITY
   ├── Built-in Envoy Stats
   │   └── Connection counters, circuit breaker stats, rate limit metrics
   ├── Custom Metrics via Lua
   │   └── WebSocket-specific counters and per-pod tracking
   ├── Prometheus Integration
   │   └── /stats/prometheus endpoint for metrics scraping
   └── Custom Endpoints
       └── Additional metrics endpoints via Lua filter

KEY IMPLEMENTATION REQUIREMENTS
===============================

1. PER-POD CONNECTION TRACKING
   Challenge: Envoy's circuit breakers operate at cluster level by default
   Solution: 
   • Use headless Kubernetes service (clusterIP: None) to expose each 
     server pod as unique endpoint
   • Configure Envoy clusters with per-host circuit breaker settings
   • Implement Lua filter to maintain per-pod connection maps

2. RATE LIMITING IMPLEMENTATION
   Token bucket algorithm for new connections
   Configurable limits:
   • connections_per_second: Global new connection rate
   • burst_capacity: Allow connection bursts
   • per_pod_max_connections: Maximum active connections per backend pod

3. REQUIRED METRICS
   • websocket_connections_active_total: Total established connections
   • websocket_connections_rejected_total: Connections rejected due to limits
   • websocket_connections_per_pod: Current connection count per server pod
   • websocket_connection_rate_limited_total: Rate limit violations

DEPLOYMENT ARCHITECTURE
=======================

1. KUBERNETES RESOURCES
   ├── Envoy Proxy Deployment
   │   └── Dedicated proxy pods (not sidecar pattern)
   ├── Headless Service
   │   └── For server pods to enable per-pod endpoint discovery
   ├── Regular Service
   │   └── To expose Envoy proxies to ALB
   └── ConfigMaps
       └── For dynamic rate limit and connection threshold configuration

2. ENVOY CONFIGURATION STRUCTURE
   listeners:
     - http_connection_manager:
         filters:
           - local_ratelimit          # New connection rate limiting
           - lua                      # Custom WebSocket connection logic
           - router                   # Traffic routing

   clusters:
     - circuit_breakers:              # Per-pod connection limits
         max_connections: N           # Configurable per backend pod
     - load_balancing_policy: LEAST_REQUEST

3. STATE MANAGEMENT
   ├── Shared Memory
   │   └── Connection counters accessible across Envoy worker threads
   ├── External Store
   │   └── Optional Redis for cluster-wide state synchronization
   └── Service Discovery
       └── Kubernetes endpoints API for dynamic backend discovery

AWS ALB CONFIGURATION
=====================

• WebSocket Support: Enable HTTP upgrade header passthrough
• Health Checks: Configure health checks for Envoy proxy pods
• Target Groups: Point to Envoy proxy service, not directly to server pods

MONITORING & OBSERVABILITY
===========================

1. METRICS COLLECTION
   ├── Prometheus
   │   └── Scrape metrics from /stats/prometheus on each Envoy pod
   ├── Custom Metrics
   │   └── Additional WebSocket-specific metrics via /websocket/metrics
   └── Grafana Dashboards
       └── Visualize connection patterns, limits, and rejections

2. ALERTING
   • High connection rejection rates
   • Per-pod connection limits approaching maximum
   • Rate limiting threshold breaches
   • Circuit breaker state changes

CHALLENGES & SOLUTIONS
======================

1. PER-POD GRANULARITY
   Challenge: Default Envoy metrics are cluster-level
   Solution: Custom Lua filter with per-upstream host tracking

2. DISTRIBUTED RATE LIMITING
   Challenge: Multiple Envoy instances need coordinated rate limiting
   Solution: External rate limit service (Redis-based) or accept 
             per-instance limits

3. WEBSOCKET STICKINESS
   Challenge: Maintaining connection affinity if required
   Solution: Configure session affinity in ALB or Envoy's consistent hashing

ALTERNATIVE IMPLEMENTATION OPTIONS
==================================

1. SERVICE MESH INTEGRATION
   ├── Istio: Built-in Envoy with policy framework
   ├── Linkerd: Lighter weight option with custom controllers
   └── Trade-off: More complexity but additional features

2. WASM EXTENSIONS
   ├── Advantage: Better performance than Lua for complex logic
   └── Trade-off: Requires compilation step and more development effort

3. CUSTOM ENVOY BUILD
   ├── Advantage: Native C++ filter for maximum performance
   └── Trade-off: Significant development and maintenance overhead

FEASIBILITY ASSESSMENT
======================

✅ HIGHLY RECOMMENDED APPROACH

This architecture leverages proven technologies and patterns:
• Envoy: Production-ready WebSocket proxying capabilities
• EKS: Mature Kubernetes platform with excellent ALB integration
• Monitoring: Standard Prometheus/Grafana observability stack

SUCCESS FACTORS:
1. Proper Lua script development for connection state management
2. Appropriate circuit breaker and rate limit tuning
3. Comprehensive monitoring and alerting setup
4. Load testing to validate connection limits and performance
5. Operational procedures for configuration updates

CONCLUSION:
The implementation is straightforward using Envoy's existing features, 
with custom Lua scripting providing the specific per-pod connection 
tracking requirements. This approach provides production-ready WebSocket 
connection management with the exact rate limiting and metrics capabilities 
specified.

================================================================================
