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
          # Rate limiting filter
          - name: envoy.filters.http.local_ratelimit
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3.LocalRateLimit
              stat_prefix: websocket_rate_limiter
              token_bucket:
                max_tokens: ${max_tokens}
                tokens_per_fill: ${tokens_per_fill}
                fill_interval: ${fill_interval}
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
          # Circuit breaker for connection limiting
          - name: envoy.filters.http.fault
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.fault.v3.HTTPFault
              abort:
                percentage:
                  numerator: 0
                  denominator: HUNDRED
                http_status: 503
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
        max_connections: ${max_connections_per_pod}
        max_pending_requests: ${max_pending_requests}
        max_requests: ${max_requests}
        max_retries: ${max_retries}
    health_checks:
    - timeout: 5s
      interval: 10s
      interval_jitter: 1s
      unhealthy_threshold: 3
      healthy_threshold: 2
      http_health_check:
        path: "/health"
        request_headers_to_add:
        - header:
            key: "x-envoy-health-check"
            value: "true"
          append: false
    load_assignment:
      cluster_name: websocket_cluster
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: ${server_service_name}.${namespace}.svc.cluster.local
                port_value: ${server_service_port}
    # Enable individual endpoint health checking and load balancing
    outlier_detection:
      consecutive_5xx: 3
      interval: 30s
      base_ejection_time: 30s
      max_ejection_percent: 50
    # Connection pool settings for WebSocket connections
    typed_extension_protocol_options:
      envoy.extensions.upstreams.http.v3.HttpProtocolOptions:
        "@type": type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions
        explicit_http_config:
          http_protocol_options:
            accept_http_10: true
        upstream_http_protocol_options:
          auto_sni: true
